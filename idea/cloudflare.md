
## `server.py` — HTTP server tối thiểu

```python
#!/usr/bin/env python3
"""Minimal sync-vault server stub for GreatDeploy tunnel spike.

Endpoints:
  GET  /health           -> {"ok": true, "ts": ...}
  GET  /manifest         -> dummy signed manifest
  GET  /item/<id>        -> dummy ciphertext envelope
  POST /item/<id>        -> echo back what client pushed

Run:  python3 server.py [port]
"""
import json, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
STORE: dict[str, bytes] = {}

class H(BaseHTTPRequestHandler):
    def _send(self, code: int, body: dict | bytes, ctype="application/json"):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/health":
            return self._send(200, {"ok": True, "ts": time.time()})
        if self.path == "/manifest":
            return self._send(200, {"v": 1, "items": list(STORE.keys()), "sig": "stub"})
        if self.path.startswith("/item/"):
            key = self.path[len("/item/"):]
            blob = STORE.get(key)
            return self._send(200 if blob else 404, blob or {"err": "not found"})
        self._send(404, {"err": "no route"})

    def do_POST(self):
        if not self.path.startswith("/item/"):
            return self._send(404, {"err": "no route"})
        key = self.path[len("/item/"):]
        n = int(self.headers.get("Content-Length", 0))
        STORE[key] = self.rfile.read(n)
        self._send(200, {"ok": True, "id": key, "bytes": n})

    def log_message(self, fmt, *args):  # quieter logs
        sys.stderr.write(f"[srv] {self.address_string()} - {fmt % args}\n")

if __name__ == "__main__":
    print(f"[srv] listening on http://127.0.0.1:{PORT}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
```

## `tunnel.sh` — boot Python server + cloudflared quick tunnel

```bash
#!/usr/bin/env bash
# tunnel.sh — spike script: run a tiny Python server behind a Cloudflare Quick Tunnel.
# Usage: ./tunnel.sh [PORT]   (default 8080)
set -euo pipefail

PORT="${1:-8080}"
LOG_DIR="$(mktemp -d -t gd-tunnel-XXXX)"
SRV_LOG="$LOG_DIR/server.log"
CF_LOG="$LOG_DIR/cloudflared.log"
SRV_PID=""
CF_PID=""

cleanup() {
  echo
  echo "[bye] shutting down..."
  [[ -n "$CF_PID"  ]] && kill "$CF_PID"  2>/dev/null || true
  [[ -n "$SRV_PID" ]] && kill "$SRV_PID" 2>/dev/null || true
  wait 2>/dev/null || true
  echo "[bye] logs kept at: $LOG_DIR"
}
trap cleanup EXIT INT TERM

# 1) Preflight
command -v cloudflared >/dev/null || {
  echo "cloudflared not found. Install:  brew install cloudflared" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 required" >&2; exit 1; }
[[ -f "./server.py" ]] || { echo "server.py not found in CWD" >&2; exit 1; }

# 2) Start local server
echo "[run] python server on :$PORT  (log: $SRV_LOG)"
python3 ./server.py "$PORT" >"$SRV_LOG" 2>&1 &
SRV_PID=$!
for i in {1..20}; do
  curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && break
  sleep 0.2
  [[ $i -eq 20 ]] && { echo "server failed to start, see $SRV_LOG"; exit 1; }
done
echo "[run] server up (pid $SRV_PID)"

# 3) Start cloudflared quick tunnel and capture the public URL
echo "[run] cloudflared tunnel --url http://localhost:$PORT  (log: $CF_LOG)"
cloudflared tunnel --no-autoupdate --url "http://localhost:$PORT" >"$CF_LOG" 2>&1 &
CF_PID=$!

PUBLIC_URL=""
for i in {1..60}; do
  PUBLIC_URL=$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' "$CF_LOG" | head -n1 || true)
  [[ -n "$PUBLIC_URL" ]] && break
  sleep 0.5
done
[[ -z "$PUBLIC_URL" ]] && { echo "could not detect tunnel URL, see $CF_LOG"; exit 1; }

echo
echo "================================================================"
echo "  Public URL : $PUBLIC_URL"
echo "  Health    : curl $PUBLIC_URL/health"
echo "  Push      : curl -X POST --data-binary @file $PUBLIC_URL/item/foo"
echo "================================================================"
echo "Press Ctrl+C to stop."
wait "$CF_PID"
```

## Chạy thử

```bash
chmod +x tunnel.sh server.py
./tunnel.sh                              # mặc định 8080

# ở terminal khác:
curl https://xxx-yyy-zzz.trycloudflare.com/health
echo "ciphertext-bytes" | curl --data-binary @- \
     https://xxx-yyy-zzz.trycloudflare.com/item/test1
curl https://xxx-yyy-zzz.trycloudflare.com/item/test1
curl https://xxx-yyy-zzz.trycloudflare.com/manifest
```

## Vài lưu ý cho spike

URL Quick Tunnel **đổi mỗi lần restart** `cloudflared` — đây chính là lý do trong Phase 3 của kế hoạch tôi đề xuất cơ chế "rebroadcast URL". Spike này giúp bạn xác nhận điều đó bằng cách dừng/khởi lại script vài lần.

Để test **độ ổn định 24h**, chạy: `nohup ./tunnel.sh > run.log 2>&1 &` rồi mỗi giờ `curl $URL/health` từ máy khác và ghi lại — nếu thấy 502/530 lác đác là bình thường với free tier, nếu rớt hẳn > vài phút thì cần xem lại.

Cloudflare Quick Tunnel **không có auth gì cả** — bất kỳ ai biết URL đều POST được. Trong spike này để trống là OK; production sẽ thay bằng header `X-Auth: HMAC(...)` như đã thiết kế trong CryptoService.

Logs nằm ở thư mục tạm in ra lúc thoát, tiện debug. Nếu muốn giữ cố định, đổi `LOG_DIR="./logs"` và `mkdir -p`.

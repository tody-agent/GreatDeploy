
# 📋 Kế hoạch phân tích & cải tiến GreatDeploy → GreatDeploy Sync

## 1. Tóm tắt nghiên cứu repo hiện tại

**GreatDeploy** hiện là một app macOS menu bar viết bằng **SwiftUI + Security.framework**, chức năng cốt lõi rất gọn:

- Lưu nhiều "profile dev" (GitHub PAT + Cloudflare API Token + git config) vào **macOS Keychain**.
- One-click switch: ghi lại Keychain entry `github.com`, chạy `git config --global`, cập nhật `~/.wrangler/config/default.toml` + `launchctl setenv`.
- Kiến trúc 3 service singleton: `KeychainService`, `GitConfigService`, `AccountStore` (ObservableObject, metadata trong UserDefaults, token trong Keychain).
- **Không sandbox** vì cần full keychain + spawn process + ghi `~/.gitconfig`.
- Chỉ chạy 1 máy, **không có cơ chế sync** giữa nhiều máy, không quản lý MCP servers / Claude skills.

→ Đây là nền rất tốt để mở rộng: app đã có quyền keychain, đã có pattern Service singleton, đã có UI menu bar.

## 2. Mục tiêu cải tiến (theo yêu cầu của bạn)

Mở rộng GreatDeploy thành **"vault đồng bộ dev-environment đa máy"** với 3 trụ cột mới:

1. **Phạm vi sync mở rộng**: ngoài accounts → thêm **MCP server configs** (`~/Library/Application Support/Claude/claude_desktop_config.json`, `.mcp.json` của Claude Code) và **Skills** (`~/.claude/skills/`, `.claude/skills/` per-project).
2. **Transport miễn phí**: dùng **Cloudflare Tunnel** (Quick Tunnel `trycloudflare.com` hoặc Named Tunnel trên domain free) để các máy nói chuyện với nhau qua HTTPS, không cần mở port / không cần VPS.
3. **Bảo mật kiểu "ví blockchain"**: dữ liệu nhạy cảm (token, PAT, API key, MCP env có secret) được **mã hoá end-to-end** bằng key dẫn xuất từ **passphrase 16 ký tự** mà chỉ máy của bạn biết. Server (cloudflare tunnel endpoint) chỉ thấy ciphertext. Text/markdown/script thường: lưu plain (hoặc chỉ sign, không encrypt) để diff/merge dễ.

## 3. Kiến trúc đề xuất

```
┌─────────────── Máy A (Hub - tuỳ chọn) ──────────────┐
│  GreatDeploy.app  (menu bar, SwiftUI)               │
│   ├─ SyncEngine                                     │
│   │    ├─ VaultStore (SQLite + file blobs)          │
│   │    ├─ CryptoService (libsodium / CryptoKit)     │
│   │    └─ HTTPServer (Vapor/Hummingbird, :7777)     │
│   └─ cloudflared (child process)                    │
│        → expose https://xxx.trycloudflare.com       │
└────────────────────┬────────────────────────────────┘
                     │  HTTPS (TLS từ Cloudflare)
                     │  Payload = AEAD ciphertext
                     ▼
┌─────────────── Máy B / C (Client) ──────────────────┐
│  GreatDeploy.app                                    │
│   ├─ SyncClient (polling + WebSocket)               │
│   ├─ CryptoService (cùng key 16 ký tự)              │
│   └─ Applier → Keychain / ~/.gitconfig /            │
│                claude_desktop_config.json /         │
│                ~/.claude/skills/                    │
└─────────────────────────────────────────────────────┘
```

Mô hình **hub-and-spoke**: 1 máy bật "Host mode" → mở cloudflared tunnel → các máy khác đăng ký URL tunnel + nhập passphrase 16 ký tự là đồng bộ được. (Không cần backend trả phí, không cần domain riêng nếu dùng Quick Tunnel.)

## 4. Thiết kế mã hoá ("ví blockchain-style")

Đây là phần quan trọng nhất, tôi đề xuất cụ thể:

**Sinh key từ passphrase 16 ký tự**

- Bạn nhập 16 ký tự (gợi ý: alphanumeric, ~95 bit entropy nếu random — đủ mạnh cho mục đích này).
- Dẫn xuất key bằng **Argon2id** (memory=64 MiB, iter=3, parallel=1) hoặc **scrypt** với salt cố định cho cả vault (lưu trong `vault_meta.json`).
- Output: 32 byte = `master_key`.

**Mã hoá từng item**

- Mỗi item nhạy cảm → `XChaCha20-Poly1305` (AEAD) với nonce ngẫu nhiên 24 byte.
- Format JSON envelope:
  ```json
  {
    "v": 1,
    "alg": "xchacha20poly1305",
    "kdf": "argon2id",
    "salt": "<base64>",
    "nonce": "<base64>",
    "ct": "<base64>",
    "aad": "github_pat:personal"
  }
  ```
- `aad` (associated data) chứa loại + tên item → chống tráo đổi ciphertext giữa các slot.

**Phân loại dữ liệu — quy tắc auto-classify**

| Loại                                                                                                         | Hành động                                                           |
| ------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| GitHub PAT, Cloudflare token, OpenAI/Anthropic key, MCP env có chứa key chứa `TOKEN/KEY/SECRET/PASSWORD` | **Encrypt** bắt buộc                                           |
| `claude_desktop_config.json` (toàn bộ)                                                                    | Parse, encrypt riêng các `env.*_KEY/_TOKEN`, phần còn lại plain |
| `.md`, `SKILL.md`, `.sh`, `.py` script trong skills                                                   | **Plain** (chỉ sign HMAC để chống sửa)                      |
| File binary trong skill                                                                                       | Plain + HMAC                                                           |

**Chữ ký toàn vault**

- Mỗi commit sync có 1 `manifest.json` (Merkle-tree đơn giản: SHA-256 của từng entry → root hash) được ký HMAC-SHA256 bằng `master_key`.
- Máy nhận: verify HMAC trước khi apply → phát hiện tampering ngay cả với file plain.

**Lưu key 16 ký tự**

- **Không bao giờ** gửi qua mạng.
- Lưu trong Keychain mỗi máy (mục `com.greatdeploy.vault.passphrase`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`).
- App khởi động lần đầu trên máy mới: hỏi user nhập 16 ký tự → test giải mã 1 sentinel record → đúng thì cache vào Keychain.

## 5. Roadmap triển khai (chia phase nhỏ, mỗi phase có thể ship)

**Phase 0 — Refactor nền (1 tuần)**

- Tách `GitAccount` thành `VaultItem` generic (`kind: .githubAccount | .cloudflareAccount | .mcpServer | .skill | .file`).
- Thêm `VaultStore` (SQLite via GRDB.swift) thay UserDefaults cho metadata.
- Viết unit test cho `KeychainService`.

**Phase 1 — CryptoService (3-5 ngày)**

- Tích hợp **swift-sodium** hoặc dùng **CryptoKit** (`ChaChaPoly` + Argon2 từ `swift-crypto-extras`).
- API: `encrypt(plaintext, aad) -> Envelope`, `decrypt(envelope, aad) -> Data`, `deriveKey(passphrase, salt)`.
- UI: màn hình "Set master passphrase" + validator (16 ký tự, hiển thị entropy).

**Phase 2 — MCP & Skills manager (1 tuần)**

- Đọc/ghi `~/Library/Application Support/Claude/claude_desktop_config.json`.
- Đọc/ghi `~/.claude/settings.json`, scan `~/.claude/skills/*/SKILL.md`.
- Hỗ trợ scope project: detect `.mcp.json`, `.claude/skills/` trong git repo đang mở.
- UI: tab mới "MCP" và "Skills" trong main window, mỗi item có icon trạng thái (synced / local-only / conflict).

**Phase 3 — Sync transport qua Cloudflare Tunnel (1-2 tuần)**

- Embed binary `cloudflared` (download lazy lần đầu).
- Host: chạy `Hummingbird` (Swift HTTP server) trên `127.0.0.1:7777` + spawn `cloudflared tunnel --url http://localhost:7777` → parse URL `https://xxx.trycloudflare.com` từ stdout → hiển thị QR code cho máy client scan.
- REST API tối thiểu:
  - `GET /manifest` → trả manifest đã ký.
  - `GET /item/:id` → trả envelope.
  - `POST /item/:id` → push envelope (yêu cầu HMAC token trong header).
  - `GET /events` (SSE) → realtime push khi có thay đổi.
- Client: thêm "Connect to Hub" → paste URL + passphrase → poll mỗi 30s + listen SSE.
- **Lưu ý bảo mật transport**: Quick Tunnel URL là public — bất kỳ ai biết URL đều gọi được. Bù lại bằng:
  - Mọi request phải có header `X-Auth: HMAC(master_key, timestamp + path)`.
  - Server từ chối nếu sai HMAC hoặc timestamp lệch > 60s (chống replay).
  - Server **không bao giờ** decrypt — chỉ trả ciphertext.

**Phase 4 — Conflict resolution & merge (1 tuần)**

- Mỗi item có `version` (vector clock {machineId: counter}).
- Conflict UI: side-by-side diff cho text, "keep mine/theirs/both" cho secret.
- Auto-merge cho file độc lập (skills khác nhau).

**Phase 5 — UX polish & hardening (1 tuần)**

- Nhập passphrase 1 lần → unlock app session (Touch ID re-auth sau X phút).
- Export/import vault (file `.gdvault` đã mã hoá) để backup offline.
- Audit log: mỗi sync ghi `who/when/what` vào local log (không lên cloud).
- Rotate passphrase: re-encrypt toàn bộ vault với key mới + bump `kdf_version`.

## 6. Những điểm cần quyết định / rủi ro

Tôi nêu để bạn cân nhắc trước khi code:

1. **Quick Tunnel vs Named Tunnel**: Quick Tunnel free thật nhưng URL đổi sau mỗi lần restart `cloudflared` → cần cơ chế "rebroadcast URL mới" (ví dụ qua 1 Gist private, hoặc dán tay). Named Tunnel cần domain trên Cloudflare (free domain `*.workers.dev` không hỗ trợ tunnel; phải có domain riêng — `.xyz` ~$1/năm là rẻ nhất).
2. **16 ký tự có đủ mạnh?** Nếu là random alphanumeric (62^16 ≈ 95 bit) → tốt cho threat model "tunnel URL bị lộ". Nếu user đặt passphrase yếu kiểu `password12345678` thì Argon2id giúp chậm brute force nhưng vẫn rủi ro. → App nên **bắt buộc generator random** hoặc cảnh báo strength.
3. **Cross-platform**: GreatDeploy hiện chỉ macOS. Nếu sau này bạn muốn sync sang Linux/Windows → phải viết client riêng (Tauri/Electron) hoặc CLI Go nhỏ. Phase 1-2 có thể chỉ macOS, Phase 3 thiết kế API cross-platform sẵn.
4. **Claude Desktop config có lock file?** Cần check — nếu Claude Desktop đang chạy mà ta ghi đè JSON, có thể bị mất hoặc app phải restart. → Hiển thị warning trước khi apply MCP changes.
5. **Lưu `cloudflared` ở đâu**: tải vào `~/Library/Application Support/GreatDeploy/bin/cloudflared`, kiểm tra checksum SHA-256 từ release GitHub chính thức của Cloudflare.

## 7. Đề xuất cấu trúc thư mục mới

```
GreatDeploy/
├── Models/
│   ├── VaultItem.swift          # mới — generic item
│   ├── Envelope.swift           # mới — crypto envelope
│   └── SyncManifest.swift       # mới
├── Services/
│   ├── KeychainService.swift    # giữ
│   ├── GitConfigService.swift   # giữ
│   ├── CryptoService.swift      # mới — XChaCha20 + Argon2
│   ├── VaultStore.swift         # mới — GRDB SQLite
│   ├── MCPConfigService.swift   # mới
│   ├── SkillsService.swift      # mới
│   ├── TunnelService.swift      # mới — quản lý cloudflared
│   ├── SyncServer.swift         # mới — Hummingbird
│   └── SyncClient.swift         # mới
├── Views/
│   ├── PassphraseSetupView.swift
│   ├── MCPListView.swift
│   ├── SkillsListView.swift
│   ├── SyncStatusView.swift
│   └── ConflictResolverView.swift
└── ...
```

## 8. Bước tiếp theo gợi ý

Nếu bạn đồng ý hướng này, tôi đề nghị bắt đầu bằng **2 việc song song**:

- **Spike 1**: viết prototype `CryptoService` Swift (~150 dòng) + test giải mã đúng/sai passphrase → xác nhận thư viện và performance Argon2id trên Mac M-series.
- **Spike 2**: viết script bash 50 dòng chạy `cloudflared tunnel --url localhost:8080` + 1 server Python tối thiểu → đo độ ổn định Quick Tunnel sau 24h (xem có rớt không, URL có thật sự giữ).

Sau khi 2 spike OK, bắt đầu Phase 0 refactor.

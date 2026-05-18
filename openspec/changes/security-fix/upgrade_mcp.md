
# Bộ tài liệu OpenSpec: `mcp-multi-platform-sync`

Dưới đây là 5 file OpenSpec, sắp xếp theo đúng layout repo (`openspec/changes/mcp-multi-platform-sync/`). Bạn paste nguyên xi vào repo, mỗi block code là một file.

---

## 📄 File 1: `openspec/changes/mcp-multi-platform-sync/proposal.md`

```markdown
# Change — MCP Multi-Platform / Multi-Device Sync

## Why

GreatDeploy hôm nay là một context switcher cho GitHub + Cloudflare.
Hệ sinh thái dev đã dịch chuyển: mỗi developer hiện cài 3-7 AI coding
tool (Claude Desktop, Cursor, VS Code Copilot, Claude Code CLI, Windsurf,
Zed, JetBrains MCP, Codex CLI, Antigravity), và mỗi tool có một file
config MCP riêng với format JSON / TOML / XML khác nhau. Khi user thêm
một MCP server mới (ví dụ một file-system server hoặc một database
server) họ phải sửa 5-9 file config khác nhau bằng tay. Khi user xoay
token API, lặp lại. Khi user dùng nhiều máy (laptop cá nhân + máy công
ty + máy bàn ở nhà), nhân lên N lần nữa.

Đây chính xác là pain point mà GreatDeploy được sinh ra để giải quyết,
chỉ là cho một loại context mới: MCP servers. Tệp khái niệm cốt lõi
của sản phẩm — Profile bundle, switch atomic, secret trong Keychain,
push protection — chuyển thẳng được sang MCP mà không phải định nghĩa
lại. Conductor (`aryabyte21/conductor`) đã chứng minh design này hoạt
động trên thực tế với 7,300+ MCP server trong registry và 9 client
adapter. Khoảng cách giữa GreatDeploy và Conductor về domain MCP
hôm nay là 100%, vì repo chưa có một dòng code MCP nào.

Đồng thời, GreatDeploy đang macOS-only và single-device. Hai hạn chế
này hợp lý cho v1 GitHub/Cloudflare nhưng không hợp lý cho MCP, vì:
(1) MCP server config là một content trí tuệ (curated set của user),
mất nó hoặc gõ lại trên máy mới là khó chịu hơn cả mất git config;
(2) AI tool tồn tại trên Linux và Windows nhiều hơn cả macOS (VS Code,
Cursor, JetBrains đều cross-platform), nên một MCP sync tool macOS-only
sẽ luôn bị xem là half-product. Change này vì vậy gói gọn cả ba mảng:
nâng MCP lên thành first-class capability, mở đường multi-device qua
iCloud / CloudKit, và refactor lớp platform để Linux/Windows có thể
ship ở v2.0 mà không cần viết lại tầng giữa.

## What changes

### Capabilities (mới)

- **mcp-bundle-management**: data model `MCPBundle`, `MCPServer`,
  `MCPClientKind`, `TransportType`; CRUD; per-bundle Keychain
  namespace; migration từ `DevProfile` cũ.
- **mcp-client-adapters**: protocol `MCPClientAdapter` và 9
  implementation (Claude Desktop, Cursor, VS Code, Claude Code CLI,
  Windsurf, Zed, JetBrains, Codex CLI, Antigravity).
- **mcp-sync-engine**: transactional sync với snapshot + verify +
  rollback; orphan tracking qua `previouslySyncedNames`; audit log.
- **mcp-registry-browse**: HTTP client cho Smithery registry; UI
  browse + install.
- **mcp-file-watcher**: phát hiện thay đổi config từ bên ngoài app;
  cập nhật detection trạng thái và notification.
- **device-sync**: provider protocol; iCloud KVS + CloudKit
  implementation; conflict resolution; secret KHÔNG sync.
- **platform-abstraction**: protocol cho Keychain / Filesystem /
  Process; MacPlatform implementation; stub cho Linux/Windows.

### Capabilities (mở rộng)

- **profile-management**: thêm field optional `mcpBundleId: UUID?`
  vào `DevProfile`; tự động tạo bundle "Default" cho mỗi profile khi
  migrate.
- **switch-engine** (từ change 004): khi switch profile thành công,
  trigger `MCPSyncEngine.sync(bundle, toClients:)`; thêm MCP vào
  snapshot / revert flow.
- **secret-storage**: thêm namespace `greatdeploy.mcp.<bundleId>.<serverId>.<envKey>`;
  bulk delete khi xoá bundle/server.
- **menu-bar-ui**: thêm submenu "MCP" với Sync Now và status indicator.

### Capabilities không thay đổi

- **safety-guard** (pre-push hook): không ảnh hưởng.
- **github-adapter**: không ảnh hưởng.
- **cloudflare-adapter**: không ảnh hưởng.

## Impact

- **Codebase**: +6,000 đến +9,000 LOC Swift, hầu hết dưới
  `GreatDeploy/MCP/`, `GreatDeploy/Sync/`, `GreatDeploy/Platform/`.
  Không refactor lớn các module đã có ngoại trừ `SwitchEngine` và
  `KeychainService` (thêm namespace, không đổi API hiện có).
- **On-disk schema**: file mới `mcp-bundles.json` bên cạnh
  `profiles.json`. Không phá vỡ `profiles.json` hiện có; chỉ thêm
  một optional field. Migration một chiều, có backup `.bak`.
- **Keychain footprint**: thêm N × M entries (N = số server, M = số
  secret env per server). Mỗi entry namespaced; bulk cleanup khi
  xoá bundle.
- **Network**: lần đầu tiên app gọi outbound HTTP đến
  `registry.smithery.ai` (chỉ khi user mở Registry tab) và iCloud
  servers (chỉ khi user bật Multi-Device Sync). Cả hai đều opt-in
  qua UI; mặc định không gọi ra ngoài.
- **Entitlements**: thêm `com.apple.developer.icloud-container-identifiers`
  và `com.apple.developer.icloud-services = CloudKit` cho phase
  multi-device. Vẫn không sandbox.
- **Phụ thuộc mới**:
  - Swift package `swift-toml` (BSD-2) cho Codex adapter, hoặc tự
    viết minimal TOML writer (≤ 200 LOC) — quyết định trong design.
  - Không dùng package XML; `XMLParser` của Foundation đủ cho
    JetBrains.
- **Hiệu năng**: sync 9 client với 10 server, mục tiêu < 2 giây
  end-to-end trên M-series. File watcher chạy ngầm, debounce 500ms.
- **Compatibility**: app vẫn build và chạy y hệt nếu user không
  bao giờ mở tab MCP — toàn bộ MCP layer lazy-init.
- **Phạm vi platform của change này**: implementation **chỉ macOS**.
  Linux/Windows được mở đường qua `PlatformAdapter` protocol nhưng
  KHÔNG được implement ở đây. Một change v2 sẽ port `MCPClientAdapter`
  sang Rust (theo pattern Conductor) và bundle qua Tauri.

## Out of scope

- Implement Linux và Windows runtime (sẽ là change riêng v2.0).
- Sync MCP server execution state (logs, restart, health checks)
  giữa các thiết bị — chỉ sync config.
- Team-shared bundle (bundle dùng chung giữa nhiều người). Phase
  này chỉ single-user multi-device.
- Sync GitHub / Cloudflare credentials qua iCloud — credentials
  vẫn local-only theo design hiện tại. Chỉ MCP bundle metadata sync.
- Tích hợp MCP server lifecycle (start/stop process) — GreatDeploy
  chỉ ghi config, không quản lý process; mỗi AI tool tự start MCP.
- Tạo / publish MCP server mới lên registry.
- OAuth flow đầy đủ cho MCP server cần OAuth (chỉ inject token đã
  có sẵn trong Keychain; OAuth bootstrap là change riêng).
- Auto-discovery của MCP server đã có sẵn trong client (Import One-Way
  từ client → bundle). Tính năng này sẽ ở change kế tiếp.
- Telemetry / analytics cho việc dùng MCP.

## Acceptance

Change này hoàn thành khi tất cả các điều kiện sau đều thoả:

1. Trên một macOS sạch, user cài GreatDeploy, vào tab "MCP", tạo
   một bundle với 3 server (1 stdio dùng `npx`, 1 SSE, 1 streamable
   HTTP), nhấn "Sync to all detected clients". Mọi client được
   detect (≥ 1) đều nhận được đúng 3 server, không phá bất kỳ
   server nào client đã có từ trước.
2. Trên cùng máy, user xoá một server khỏi bundle, nhấn Sync lại.
   Server đó biến mất khỏi mọi client mà KHÔNG đụng đến server
   user-added khác.
3. Sửa file config của một client trực tiếp bằng `vim`. Trong
   vòng ≤ 2 giây, GreatDeploy nhận diện và hiển thị badge "External
   changes detected" trên client đó.
4. Force fail adapter thứ N (qua test seam) khi sync. Verify rằng
   N-1 client đầu tiên được rollback byte-for-byte về content
   trước sync; audit log có entry chi tiết; user nhận notification
   với error message human-readable.
5. Bật Multi-Device Sync, đăng nhập cùng iCloud account trên máy
   thứ hai. Sửa bundle trên máy A, trong vòng ≤ 60 giây máy B thấy
   thay đổi. Mỗi server có secret hiển thị badge "🔑 Missing secret
   on this device" cho đến khi user paste lại token.
6. Xoá bundle trên máy A. Verify: toàn bộ Keychain entries namespace
   `greatdeploy.mcp.<bundleId>.*` bị xoá; file `mcp-bundles.json`
   không còn entry; trên máy B, bundle biến mất trong ≤ 60 giây.
7. `profiles.json` của user existing được preserved nguyên trạng;
   `mcp-bundles.json` mới sinh ra với một bundle "Default" rỗng
   cho mỗi profile; backup `profiles.json.bak.<timestamp>` tồn tại.
8. `xcodebuild test` xanh; coverage cho `MCP/` module ≥ 70% line
   coverage và 100% trên `MCPSyncEngine.swift` và mọi serializer.
9. Khi user chưa bao giờ mở tab MCP, app không tạo `mcp-bundles.json`,
   không gọi network, không spawn file watcher — verified bằng
   `fs_usage` và `nettop` trong manual smoke test.
10. Tất cả secret được redacted trong audit log; `grep -r <token>
    ~/Library/Logs/GreatDeploy/` trả về 0 dòng.
```

---

## 📄 File 2: `openspec/changes/mcp-multi-platform-sync/design.md`

```markdown
# Design — MCP Multi-Platform / Multi-Device Sync

## Context & Technical Approach

GreatDeploy hôm nay là một SwiftUI menu bar app với ba service singleton
(`KeychainService`, `GitConfigService`, `GitHubCLIService`), một
`AccountStore` `@MainActor` `ObservableObject`, và một model
`DevProfile`. Toàn bộ ghi đĩa đi qua atomic-write pattern (write `.tmp`,
rename); toàn bộ secret đi qua Keychain với namespace dạng
`greatdeploy.<scope>.<id>`. Code dùng `Process()` cho subprocess,
`Security.framework` cho Keychain, `NSStatusItem` cho menu bar.

Conductor (`aryabyte21/conductor`) đã giải bài toán MCP sync cho
chính xác 9 client mà GreatDeploy cần support. Design của Conductor
xoay quanh bốn primitive:

1. **`McpServerConfig`** — value type thống nhất với `transport`,
   `command`, `args`, `env`, `url`, `secret_env_keys`.
2. **`ClientAdapter` trait** — bốn method `id / config_path /
   read_servers / write_servers`.
3. **Merge-based write với `previously_synced_names`** — cumulative
   set để phân biệt orphan của tool ta vs server user-added.
4. **Verify-after-write + rollback** — đọc lại config vừa ghi, nếu
   server expected không xuất hiện thì restore content cũ.

Approach của change này là **port 1-1 bốn primitive đó sang Swift**,
gói trong namespace `GreatDeploy.MCP.*`, tích hợp với `SwitchEngine`
đã được spec hoá ở change 004, và bọc thêm hai lớp mới mà Conductor
không có: `DeviceSyncProvider` (iCloud) và `PlatformAdapter` (chuẩn
bị cho Linux/Windows).

Quyết định kiến trúc lớn nhất là **giữ Swift làm ngôn ngữ tầng giữa
ở phase này**, không rewrite sang Rust như Conductor. Lý do: (a) toàn
bộ codebase hiện tại là Swift, rewrite đồng nghĩa với hai năm refactor;
(b) `PlatformAdapter` protocol cho phép thay implementation mà không
đổi caller, nên migration sang Rust (nếu cần) là một change v2 độc
lập, không phải tiền đề của v1; (c) Swift trên Linux đã ổn định ở mức
"đủ cho daemon CLI" với swift-corelibs-foundation, đủ cho 80%
MCPClientAdapter chạy được không phải rewrite.

## Architecture Change

```

BEFORE (today):

```
┌─────────────────────────────────────────────────────────────┐
│  SwiftUI Views                                              │
├─────────────────────────────────────────────────────────────┤
│  AccountStore (@MainActor, ObservableObject)                │
├──────────────┬──────────────┬───────────────────────────────┤
│ GitHub       │ Cloudflare   │  KeychainService              │
│ via Process  │ Adapter      │                               │
└──────────────┴──────────────┴───────────────────────────────┘
```

AFTER (this change):

```
┌─────────────────────────────────────────────────────────────┐
│  SwiftUI Views   [+ MCP tab, Registry, Multi-Device tab]    │
├─────────────────────────────────────────────────────────────┤
│  AccountStore           ⇆   MCPBundleStore                   │
├─────────────────────────────────────────────────────────────┤
│            SwitchEngine (transactional, atomic)              │
│  ┌──────────┐ ┌──────────┐ ┌─────────────────────────────┐  │
│  │ GitHub   │ │Cloudflare│ │ MCPSyncAdapter              │  │
│  │ Adapter  │ │ Adapter  │ │   ↓ orchestrates             │  │
│  │          │ │          │ │ [9× MCPClientAdapter]        │  │
│  └──────────┘ └──────────┘ └─────────────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  MCPSyncEngine • MCPFileWatcher • SmitheryClient            │
├─────────────────────────────────────────────────────────────┤
│  DeviceSyncProvider  ←→  iCloudSyncProvider (KVS+CloudKit)   │
├─────────────────────────────────────────────────────────────┤
│  PlatformAdapter (protocol)                                  │
│       ↓ macOS impl              ↓ stub linux/windows         │
│  MacPlatform { Keychain, FileSystem, Process }              │
└─────────────────────────────────────────────────────────────┘
```

## Proposed Changes

### 1. New module: `GreatDeploy/MCP/Models/`

#### `MCPServer.swift`

Value type, `Codable`, `Sendable`, `Hashable`. Tách hoàn toàn khỏi

`DevProfile`. Field tương đương `McpServerConfig` của Conductor:

`id: UUID`, `name: String` (unique trong bundle), `displayName: String?`,

`description: String?`, `enabled: Bool`, `transport: TransportType`,

`command: String?` (stdio), `args: [String]`, `env: [String: String]`

(serialize KHÔNG kèm value của key trong `secretEnvKeys`),

`url: String?` (cho sse/http), `secretEnvKeys: [String]`,

`tags: [String]`, `source: String?`, `registryId: String?`,

`createdAt: Date`, `updatedAt: Date`.

Tuân thủ y nguyên security pattern đã có trong `DevProfile.Codable`:

custom `init(from:)` và `encode(to:)` đảm bảo value của key trong

`secretEnvKeys` không bao giờ xuất hiện trong `env` được encode ra

JSON; chúng chỉ tồn tại trong memory sau khi `MCPSyncEngine` hydrate

từ Keychain. `description` (CustomStringConvertible) redact giá trị

env. `debugDescription` redact.

#### `MCPBundle.swift`

`id: UUID`, `name: String`, `servers: [MCPServer]`,

`enabledClients: Set<MCPClientKind>`, `createdAt: Date`,

`updatedAt: Date`, `deviceOrigin: String?` (UUID máy tạo, dùng cho

conflict resolution multi-device).

#### `MCPClientKind.swift`

```swift
enum MCPClientKind: String, Codable, CaseIterable, Sendable {
    case claudeDesktop
    case cursor
    case vscode
    case claudeCode
    case windsurf
    case zed
    case jetbrains
    case codex
    case antigravity
}
```

Mỗi case có computed `displayName`, `iconName`, và static method

`adapter()` trả `MCPClientAdapter` tương ứng.

#### `TransportType.swift`

```swift
enum TransportType: String, Codable, Sendable {
    case stdio, sse, streamableHttp
}
```

#### `MCPSyncState.swift`

Per-client state. Field `clientId: MCPClientKind`,

`lastSyncedAt: Date?`, `lastSyncedServerNames: [String]`,

`previouslySyncedNames: Set<String>` (CUMULATIVE — đây là field

quan trọng nhất cho orphan tracking, copy y nguyên semantics của

Conductor’s `previously_synced_names`).

### 2. New module: `GreatDeploy/MCP/Adapters/`

#### `MCPClientAdapter.swift` (protocol)

```swift
protocol MCPClientAdapter: Sendable {
    var kind: MCPClientKind { get }
    var displayName: String { get }
    func configPath() -> URL?
    func detect() -> Bool
    func readServers() throws -> [MCPServer]
    func writeServers(
        _ servers: [MCPServer],
        existingContent: String?,
        previouslySyncedNames: Set<String>
    ) throws
}
```

Convention: nếu `configPath()` trả nil hoặc file không tồn tại nhưng

thư mục cha tồn tại (ví dụ `~/.cursor/` tồn tại nhưng `mcp.json` chưa

có), `detect()` trả `true` (client đã cài). Nếu thư mục cha cũng

không có, `detect()` trả `false`.

`writeServers` phải atomic (qua `.tmp` + rename), phải tạo backup

`<path>.bak.<ISO8601>` trước khi ghi, và phải merge theo công thức:

```
final = (existing ∖ previouslySyncedNames) ∪ servers
```

Trong đó `∖` là set-difference theo `name`. Logic này đảm bảo:

* Server user thêm thẳng vào client (chưa từng nằm trong

  `previouslySyncedNames`) được giữ nguyên.
* Server GreatDeploy từng sync nhưng đã bị xoá khỏi bundle (trong

  `previouslySyncedNames` nhưng không trong `servers`) bị remove khỏi

  client → đây là cơ chế orphan cleanup.
* Server đang trong bundle (trong `servers`) ghi đè bản cũ cùng tên.

#### 9 implementation: `ClaudeDesktopAdapter.swift`, `CursorAdapter.swift`, `VSCodeAdapter.swift`, `ClaudeCodeAdapter.swift`, `WindsurfAdapter.swift`, `ZedAdapter.swift`, `JetBrainsAdapter.swift`, `CodexAdapter.swift`, `AntigravityAdapter.swift`

Mỗi file ~150-300 LOC. Tham chiếu fixture từ Conductor để verify

schema. JetBrains cần `XMLParser` Foundation (delegate-based parsing,

viết một wrapper SAX → DOM mini ≤ 150 LOC). Codex cần TOML — quyết

định trong design: **tự viết minimal TOML writer ≤ 200 LOC** vì subset

TOML cần dùng rất hẹp (key-value, array, nested table); thêm

dependency cho ~200 LOC không đáng. Đọc TOML từ file dùng cùng writer

ở chiều ngược lại.

### 3. New module: `GreatDeploy/MCP/Serializers/`

`JSONMerger.swift` — đọc Data → `[String: Any]` qua

`JSONSerialization`, thực hiện merge trên key `mcpServers` (hoặc tên

key tương ứng từng client), serialize lại với

`.sortedKeys + .prettyPrinted` để diff git stable. Phải preserve

mọi key top-level khác (ví dụ `theme` của Cursor) tuyệt đối không

đụng vào.

`XMLSerializer.swift` — minimal XML cho JetBrains MCP element tree.

`TOMLSerializer.swift` — minimal TOML cho Codex `~/.codex/config.toml`.

### 4. New module: `GreatDeploy/MCP/Sync/`

#### `MCPSyncEngine.swift`

Actor-isolated (Swift concurrency, không phải `@MainActor`).

```swift
actor MCPSyncEngine {
    func sync(
        bundle: MCPBundle,
        toClients clients: Set<MCPClientKind>
    ) async -> [MCPSyncResult]
}
```

Per-client flow (port từ `sync_to_client` trong Conductor’s `sync.rs`):

1. Lấy adapter qua `client.adapter()`.
2. Nếu `!adapter.detect()` → skip với result `success=true, written=0`.
3. Inject secrets: với mỗi server trong bundle, copy → mutable, với

   mỗi key trong `secretEnvKeys` đọc Keychain entry

   `greatdeploy.mcp.<bundleId>.<server.id>.<key>` và gán vào

   `env[key]`. Nếu Keychain miss → push warning, continue (fault-

   tolerant, không fail toàn bộ sync).
4. Đọc `existingContent` từ `configPath()` (capture cho rollback).
5. Lấy `previouslySyncedNames` từ `MCPSyncState[client]`. Nếu state

   tồn tại nhưng `previouslySyncedNames` rỗng (migration seed), đọc

   `adapter.readServers()` hiện tại để khởi tạo baseline — giống

   pattern Conductor.
6. `adapter.writeServers(enrichedServers, existingContent, previouslySyncedNames)`.
7. **Verify** : gọi `adapter.readServers()` lần nữa, đảm bảo mọi

   [server.name](http://server.name/) trong `enrichedServers` xuất hiện. Nếu thiếu →

   rollback bằng cách atomic-write lại `existingContent`. Trả result

   `success=false`.

1. Update `MCPSyncState`: `lastSyncedAt = now`,

   `lastSyncedServerNames = enrichedServers.map(\.name)`,

   `previouslySyncedNames.formUnion(lastSyncedServerNames)`.
2. Append audit log entry (không có secret).

Toàn bộ flow cho mỗi client phải finish hoặc rollback trước khi

client tiếp theo bắt đầu (sequential per client để đơn giản hoá

rollback semantic; song song có thể là optimization sau).

#### `MCPSyncResult.swift`

```swift
struct MCPSyncResult: Sendable {
    let client: MCPClientKind
    let success: Bool
    let serversWritten: Int
    let error: String?
    let warnings: [String]
    let durationMs: Int
}
```

#### `MCPSyncAdapter.swift`

Wrapper conform `AdapterProtocol` của change 004, để

`MCPSyncEngine.sync(...)` được gọi atomic trong `SwitchEngine`

transaction khi user switch DevProfile. `snapshot()` của adapter

này capture `existingContent` của TẤT CẢ client; `revert()` ghi lại

từng cái. Đây là cách MCP tích hợp vào atomic switch flow.

### 5. New module: `GreatDeploy/MCP/Registry/`

`SmitheryClient.swift` — URLSession-based HTTP client gọi

`https://registry.smithery.ai/servers?q=...` (endpoint cần verify

trong implementation). Trả `[RegistryEntry]`. Cache 10 phút trong

memory. Network failure → fail open với empty list + banner.

`MCPRegistryView.swift` — search box, list view, nút “Install to

current bundle” tạo `MCPServer` từ registry entry và push vào

`MCPBundleStore`.

### 6. New module: `GreatDeploy/MCP/Watcher/`

`MCPFileWatcher.swift` — singleton, dùng `DispatchSource.makeFileSystem ObjectSource(fileDescriptor:eventMask:queue:)` với event mask

`.write | .rename | .delete`. Một file descriptor cho mỗi

`configPath()` đã detect. Debounce 500ms (nếu nhiều event trong cửa

sổ debounce thì coi là một). Publish event qua Combine subject; UI

subscribe và refresh `MCPClientsSyncView`.

Setting `notifyExternalChanges` (mặc định `true`) — khi event đến

và lần ghi gần nhất từ GreatDeploy đã > 5 giây, hiện notification

“Cursor’s MCP config changed externally. Re-sync?” với action button.

### 7. New module: `GreatDeploy/Sync/`

#### `DeviceSyncProvider.swift` (protocol)

```swift
protocol DeviceSyncProvider: Sendable {
    func push(_ bundles: [MCPBundle]) async throws
    func pull() async throws -> [MCPBundle]
    func subscribe(onChange: @escaping ([MCPBundle]) -> Void)
}
```

#### `ICloudSyncProvider.swift`

Dùng `NSUbiquitousKeyValueStore` cho danh sách compact

`[bundleId: updatedAt]` (instant sync, size < 1KB). Dùng

`CKContainer.default().privateCloudDatabase` cho payload thực

(`CKRecord` type `MCPBundle` với field `payload: CKAsset` chứa

JSON, `updatedAt: Date`, `deviceOrigin: String`).

Push: encode `MCPBundle` → JSON Data → ghi vào temp file →

`CKAsset(fileURL:)` → save record. Sau đó update KVS với cặp

`(bundleId, updatedAt)`.

Pull: query records updated since last pull timestamp; decode JSON

từ `CKAsset`; merge vào `MCPBundleStore` local theo

`ConflictResolver`.

Subscribe: dùng `CKQuerySubscription` để push notification khi có

record thay đổi từ device khác; Combine bridge cho UI.

#### `ConflictResolver.swift`

Per-server level conflict resolution, không per-bundle. Với mỗi

`(localServer, remoteServer)` cùng `id`, so sánh `updatedAt`:

* Remote mới hơn → replace local.
* Local mới hơn → keep, push lại.
* Cùng timestamp → so sánh content hash; nếu khác → flag conflict

  trong UI, default keep local, cho user resolve thủ công.

Bundle-level: cùng logic cho metadata `name`, `enabledClients`.

 **Secret KHÔNG sync** . Sau pull, mỗi `MCPServer` có

`secretEnvKeys.isEmpty == false` mà device hiện tại không tìm thấy

Keychain entry tương ứng → flag `missingSecretsOnThisDevice = true` (computed property, không serialize). UI hiển thị badge.

### 8. New module: `GreatDeploy/Platform/`

#### `PlatformAdapter.swift` (protocol)

```swift
protocol PlatformAdapter: Sendable {
    var secretStore: SecretStore { get }
    var fileSystem: FileSystem { get }
    var processRunner: ProcessRunner { get }
    var appSupportDirectory: URL { get }
    var logsDirectory: URL { get }
}

protocol SecretStore: Sendable {
    func read(service: String, account: String) throws -> String?
    func write(service: String, account: String, value: String) throws
    func delete(service: String, account: String) throws
    func deleteAll(servicePrefix: String) throws  // bulk cleanup
}

protocol FileSystem: Sendable {
    func atomicWrite(_ data: Data, to url: URL) throws
    func readData(from url: URL) throws -> Data?
    func exists(_ url: URL) -> Bool
    func backup(_ url: URL) throws -> URL
}

protocol ProcessRunner: Sendable {
    func run(
        _ executable: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> ProcessResult
}
```

#### `MacPlatform.swift`

Wraps existing `KeychainService`, file APIs, và `Process()` từ

codebase hiện tại. Không thay đổi hành vi; chỉ phơi qua protocol.

Phase 0 là refactor pure.

#### Stubs

`LinuxPlatform.swift` và `WindowsPlatform.swift` với `#if os(...)`

guard và một implementation `fatalError("Not implemented in this release")`. Mục đích: compile-time hint cho future change.

### 9. Mở rộng module hiện có

#### `Models/DevProfile.swift`

Thêm field optional:

```swift
var mcpBundleId: UUID?
```

`CodingKeys` thêm case `mcpBundleId`, decode dùng `decodeIfPresent`

để tương thích ngược.

#### `Services/AccountStore.swift`

Trong `addAccount` mặc định tạo một `MCPBundle` tên `"<displayName> MCP"` và gán `mcpBundleId`. Trong `removeAccount` xoá bundle tương

ứng (gọi `MCPBundleStore.delete(_:)` để bulk-clean Keychain).

#### `Services/KeychainService.swift`

Thêm methods cho namespace mới:

```swift
func saveMCPSecret(bundleId: UUID, serverId: UUID, envKey: String, value: String) throws
func readMCPSecret(bundleId: UUID, serverId: UUID, envKey: String) throws -> String?
func deleteMCPSecret(bundleId: UUID, serverId: UUID, envKey: String) throws
func deleteAllMCPSecrets(bundleId: UUID) throws  // bulk on bundle deletion
```

Service prefix: `greatdeploy.mcp.<bundleId-uuid-string>.`

#### `Services/SwitchEngine.swift` (từ change 004)

`adapters` list thêm `MCPSyncAdapter` ở cuối thứ tự (sau Cloudflare).

Lý do: MCP sync là phần phục hồi được dễ nhất (chỉ cần re-write

config), nên nếu fail ở MCP sync thì rollback chi phí thấp; còn nếu

GitHub/Cloudflare fail thì không nên đụng MCP.

### 10. New views

`MCPServersListView.swift`, `MCPServerEditorView.swift`,

`MCPClientsSyncView.swift`, `MCPRegistryView.swift`,

`MultiDeviceSyncSettingsView.swift`. Tham chiếu UI hiện có của

`AddEditAccountView` để consistency.

## Data Flow Diagrams

### Flow: User adds a server and syncs

```
User → MCPServerEditorView → MCPBundleStore.upsert(server)
     ↓                              ↓
     ↓                      KeychainService.saveMCPSecret(env values)
     ↓                              ↓
     ↓                      atomic-write mcp-bundles.json (NO secret values)
     ↓
User → MCPClientsSyncView → "Sync All" button → MCPSyncEngine.sync(bundle, toClients: enabled)
                                                          ↓
                          For each MCPClientKind in enabledClients:
                              ↓
                          1. adapter = kind.adapter()
                          2. if !adapter.detect() → skip
                          3. enriched = inject secrets from Keychain into env
                          4. existingContent = read configPath()
                          5. previouslySynced = MCPSyncState[kind].previouslySyncedNames
                          6. adapter.writeServers(enriched, existingContent, previouslySynced)
                          7. verify: adapter.readServers() ⊇ enriched.names
                          8. if verify fails → atomic-write existingContent back, return failure
                          9. update MCPSyncState
                          10. audit log (no secrets)
```

### Flow: Multi-device sync push

```
MCPBundleStore.upsert(...) → didChange signal
                                  ↓
                         (debounce 30s)
                                  ↓
                         ICloudSyncProvider.push(bundles)
                                  ↓
                  ┌───────────────┴───────────────┐
                  ↓                               ↓
        NSUbiquitousKeyValueStore        CloudKit private DB
        (bundle index, < 1KB)            (CKRecord per bundle, JSON asset)
                                  ↓
                         (other device's KVS observer fires)
                                  ↓
                         ICloudSyncProvider.pull() on other device
                                  ↓
                         ConflictResolver.merge(local, remote)
                                  ↓
                         MCPBundleStore.applyRemote(...)
                                  ↓
                         (server with missing secret → badge in UI)
```

## Verification Strategy

* Unit test mỗi adapter với fixture JSON/TOML/XML thực tế (thu thập

  từ máy dev có cài 9 client).
* Unit test `MCPSyncEngine` với mock `MCPClientAdapter` và fault

  injection ở bước 6, 7 — verify rollback byte-for-byte.
* Unit test `ConflictResolver` với 4 scenario: local-newer,

  remote-newer, same-timestamp-diff-content, identical.
* Snapshot test cho merge logic của `JSONMerger` với 5 input JSON

  có chứa server user-added xen với server GreatDeploy-managed.
* Integration test: spin up một fake `Claude Desktop config dir`

  trong tmpdir, run full sync, parse lại, assert.
* Security test: regex `grep -E '[a-zA-Z0-9]{32,}'` (token-like

  strings) trên toàn bộ `mcp-bundles.json` và `audit.log` sau khi

  test suite chạy xong — phải zero match.
* Performance test: sync 9 client × 10 server, target < 2s end-to-end

  trên reference machine (M2 MacBook Air, macOS 14).

## Compatibility / Migration

* File `mcp-bundles.json` mặc định **không tồn tại** sau update;

  được tạo lazily khi user lần đầu mở tab MCP HOẶC khi

  `AccountStore` chạy migration. Migration logic:

  1. Đọc `profiles.json`.
  2. Với mỗi profile có `mcpBundleId == nil`, tạo một

     `MCPBundle(name: "\(profile.displayName) MCP", servers: [])`,

     gán `profile.mcpBundleId = bundle.id`.
  3. Atomic-write `mcp-bundles.json`.
  4. Backup `profiles.json` thành `profiles.json.bak.<timestamp>`.
  5. Atomic-write `profiles.json` (với field mới).
  6. Idempotent: nếu tất cả profile đã có `mcpBundleId`, skip.
* Keychain layout cũ KHÔNG đổi. Namespace MCP thêm vào hoàn toàn

  mới, không đụng entries của GitHub/Cloudflare.
* Nếu user downgrade ngược về version pre-MCP, `mcp-bundles.json`

  sẽ bị bỏ qua (không có code đọc), và field `mcpBundleId` trong

  `profiles.json` cũng bị bỏ qua (decoder cũ ignore unknown key).

  Không phá user data.

## Open Questions

1. **Smithery registry endpoint** : URL chính xác và format response

   cần verify trong Phase 4. Nếu API thay đổi, fallback browse-only

   với danh sách hardcoded server phổ biến.

1. **iCloud container ID** : cần Apple Developer account để cấu

   hình. Nếu chưa có, Phase 5 ship một stub provider in-memory để

   test, và mở change con để enable iCloud production.

1. **JetBrains XML schema** : mỗi IDE (IntelliJ, PyCharm, GoLand…)

   có thư mục riêng. Hỏi mở: sync tất cả hay chỉ IDE active?  **Quyết

   định trong implementation** : sync tất cả IDE detect được, giống

   Conductor (nó dùng glob `~/Library/Application Support/JetBrains/*/options/mcp.xml`).

1. **VS Code workspace vs user config** : VS Code MCP có thể ở user

   level (`~/Library/Application Support/Code/User/mcp.json`) hoặc

   workspace level (`.vscode/mcp.json`). Phase 2 chỉ làm user level;

   workspace level deferred.

1. **Codex TOML library** : tự viết hay add dependency.  **Quyết

   định** : tự viết, ≤ 200 LOC, để tránh dependency surface mới.

## Risk Register

| Risk                                         | Mitigation                                                                                   |
| -------------------------------------------- | -------------------------------------------------------------------------------------------- |
| Format drift khi client update               | Adapter version-aware, merge-based preserve unknown fields                                   |
| Keychain prompt flood khi sync nhiều server | Dùng `kSecAttrAccessGroup`, batch read                                                    |
| CloudKit quota / rate limit                  | Debounce push 30s, batch operations, surface quota error trong UI                            |
| File watcher leak fd                         | Cleanup observers trong `deinit`, max 9 fd (1 per client)                                  |
| Migration corrupt profiles.json              | Backup BẮT BUỘC trước migration, abort nếu backup fail                                  |
| User secret leak qua audit log               | Audit log chỉ chứa[server.name](http://server.name/)+ envKey (không value), test grep verify |
| Multi-device split-brain                     | Per-server timestamp, conflict UI flag, không silent overwrite                              |
| User downgrade phá data                     | Forward-compatible decoder (decodeIfPresent), bundle file ignored by old version             |

```

---

## 📄 File 3: `openspec/changes/mcp-multi-platform-sync/tasks.md`

```markdown
# Implementation Checklist — MCP Multi-Platform / Multi-Device Sync

## Phase 0: Platform Abstraction (3-5 days)

### 0.1 Setup
- [ ] 0.1.1 Tạo folder structure: `GreatDeploy/MCP/{Models,Adapters,Serializers,Sync,Registry,Watcher,Views}`, `GreatDeploy/Sync/`, `GreatDeploy/Platform/`
- [ ] 0.1.2 Update `project.yml` để XcodeGen pick up folder mới
- [ ] 0.1.3 Run `./sync-project.sh`, verify build vẫn xanh

### 0.2 Platform protocol
- [ ] 0.2.1 `Platform/PlatformAdapter.swift` — protocol định nghĩa SecretStore, FileSystem, ProcessRunner
- [ ] 0.2.2 `Platform/SecretStore.swift` — protocol
- [ ] 0.2.3 `Platform/FileSystem.swift` — protocol
- [ ] 0.2.4 `Platform/ProcessRunner.swift` — protocol
- [ ] 0.2.5 `Platform/MacPlatform.swift` — implementation wrap code hiện có
- [ ] 0.2.6 `Platform/LinuxPlatform.swift.stub` và `WindowsPlatform.swift.stub` với fatalError + `#if os(...)` guard
- [ ] 0.2.7 Inject `PlatformAdapter` qua `@Environment` hoặc singleton `Platform.current`

### 0.3 Refactor existing services
- [ ] 0.3.1 `KeychainService` conform `SecretStore` (giữ API cũ public, internal qua protocol)
- [ ] 0.3.2 Atomic write helper conform `FileSystem.atomicWrite`
- [ ] 0.3.3 `Process()` callsites đi qua `ProcessRunner.run`
- [ ] 0.3.4 Verify không có hành vi nào bị thay đổi: run full test suite

### 0.4 Phase 0 acceptance
- [ ] 0.4.1 Build xanh trên `xcodebuild`
- [ ] 0.4.2 Test suite hiện có pass 100%
- [ ] 0.4.3 Tag `v1.0.x-phase0` (internal)

## Phase 1: MCP Models + Storage (5-7 days)

### 1.1 Models
- [ ] 1.1.1 `MCP/Models/TransportType.swift` — enum
- [ ] 1.1.2 `MCP/Models/MCPClientKind.swift` — enum + displayName/iconName
- [ ] 1.1.3 `MCP/Models/MCPServer.swift` — value type với security-safe Codable (PAT pattern)
- [ ] 1.1.4 `MCP/Models/MCPBundle.swift` — value type
- [ ] 1.1.5 `MCP/Models/MCPSyncState.swift` — per-client state
- [ ] 1.1.6 `MCP/Models/MCPSyncResult.swift` — result type

### 1.2 Storage
- [ ] 1.2.1 `MCP/MCPBundleStore.swift` — `@MainActor ObservableObject`, CRUD bundle, atomic-write `mcp-bundles.json`
- [ ] 1.2.2 Keychain namespace methods trong `KeychainService`: `saveMCPSecret`, `readMCPSecret`, `deleteMCPSecret`, `deleteAllMCPSecrets(bundleId:)`
- [ ] 1.2.3 Bundle delete → bulk Keychain cleanup
- [ ] 1.2.4 Server delete → cleanup các Keychain entry của server đó

### 1.3 Migration
- [ ] 1.3.1 Thêm field `mcpBundleId: UUID?` vào `DevProfile`
- [ ] 1.3.2 Update `DevProfile.CodingKeys` với `decodeIfPresent`
- [ ] 1.3.3 Migration function trong `AccountStore.loadAccounts`: tạo bundle "Default" cho profile chưa có `mcpBundleId`
- [ ] 1.3.4 Backup `profiles.json` trước migration; abort migration nếu backup fail
- [ ] 1.3.5 Idempotency check

### 1.4 Tests
- [ ] 1.4.1 `MCPServerCodableTests` — verify secret env values KHÔNG xuất hiện trong JSON
- [ ] 1.4.2 `MCPBundleStoreTests` — CRUD happy path
- [ ] 1.4.3 `MCPBundleStoreTests` — atomic write + corrupted file recovery
- [ ] 1.4.4 `MigrationTests` — empty/happy/already-migrated/corrupted input
- [ ] 1.4.5 `KeychainNamespaceTests` — bulk delete xoá đúng namespace

### 1.5 Phase 1 acceptance
- [ ] 1.5.1 Coverage `MCP/Models/` ≥ 80%
- [ ] 1.5.2 Coverage `MCPBundleStore` 100%
- [ ] 1.5.3 Smoke test: launch app, verify không tạo `mcp-bundles.json` cho đến khi user tương tác

## Phase 2: Core Adapters (10-14 days)

### 2.1 Adapter protocol & serializers
- [ ] 2.1.1 `MCP/Adapters/MCPClientAdapter.swift` — protocol
- [ ] 2.1.2 `MCP/Serializers/JSONMerger.swift` — merge logic + tests
- [ ] 2.1.3 Helper `mergeServers(existing:, managed:, previouslySynced:)` pure function với coverage 100%

### 2.2 Claude Desktop
- [ ] 2.2.1 `MCP/Adapters/ClaudeDesktopAdapter.swift`
- [ ] 2.2.2 Fixture `Tests/Fixtures/claude_desktop_config.json` (3 server, 1 user-added)
- [ ] 2.2.3 Snapshot test read/write/merge

### 2.3 Cursor
- [ ] 2.3.1 `MCP/Adapters/CursorAdapter.swift`
- [ ] 2.3.2 Fixture + tests

### 2.4 VS Code (user level only)
- [ ] 2.4.1 `MCP/Adapters/VSCodeAdapter.swift`
- [ ] 2.4.2 Fixture + tests
- [ ] 2.4.3 Document workspace-level deferred

### 2.5 Claude Code CLI
- [ ] 2.5.1 `MCP/Adapters/ClaudeCodeAdapter.swift`
- [ ] 2.5.2 Fixture (parse subset của `~/.claude/settings.json` chỉ chạm `mcpServers`)
- [ ] 2.5.3 Tests preserve mọi key non-MCP

### 2.6 Verify-after-write
- [ ] 2.6.1 Sau mỗi `writeServers` test, gọi `readServers` lại và assert tập hợp khớp

### 2.7 Phase 2 acceptance
- [ ] 2.7.1 4 adapter pass 100% fixture tests
- [ ] 2.7.2 Manual test: sync vào 4 client thật trên máy dev, mở từng app verify

## Phase 3: Sync Engine + UI (7-10 days)

### 3.1 Engine
- [ ] 3.1.1 `MCP/Sync/MCPSyncEngine.swift` — actor, sync(bundle:toClients:)
- [ ] 3.1.2 Secret injection từ Keychain
- [ ] 3.1.3 Capture existingContent trước write
- [ ] 3.1.4 Verify-after-write
- [ ] 3.1.5 Rollback bằng atomic-write existingContent
- [ ] 3.1.6 Audit log `~/Library/Logs/GreatDeploy/mcp-audit.log` — append only, NO secrets

### 3.2 SwitchEngine integration
- [ ] 3.2.1 `MCP/Sync/MCPSyncAdapter.swift` — conform `AdapterProtocol` của change 004
- [ ] 3.2.2 `snapshot()` capture existingContent của tất cả enabledClient
- [ ] 3.2.3 `revert(snapshot:)` ghi lại từng client
- [ ] 3.2.4 Đăng ký vào `SwitchEngine.adapters` order: GitHub → Cloudflare → MCP

### 3.3 UI: MCP tab
- [ ] 3.3.1 `MCP/Views/MCPServersListView.swift` — table view + add/edit/delete
- [ ] 3.3.2 `MCP/Views/MCPServerEditorView.swift` — form với transport picker, secret env toggle
- [ ] 3.3.3 `MCP/Views/MCPClientsSyncView.swift` — list 9 client, detect badge, toggle enable, "Sync All" button
- [ ] 3.3.4 Hook tab vào main window navigation
- [ ] 3.3.5 Menu bar submenu "MCP" với "Sync Now" item + last-sync status

### 3.4 Tests
- [ ] 3.4.1 `MCPSyncEngineTests` — happy path 1 client 3 server
- [ ] 3.4.2 `MCPSyncEngineTests` — fail-on-N-th-adapter, verify rollback byte-for-byte
- [ ] 3.4.3 `MCPSyncEngineTests` — Keychain miss → warning, không fail
- [ ] 3.4.4 `MCPSyncEngineTests` — verify-after-write detect missing server → rollback
- [ ] 3.4.5 Security test: grep `~/Library/Logs/GreatDeploy/` không có token-like string
- [ ] 3.4.6 Snapshot test: SwiftUI views render với 0/1/10 server

### 3.5 Phase 3 acceptance
- [ ] 3.5.1 End-to-end manual: tạo 3 server, sync, mở 4 client, verify
- [ ] 3.5.2 Coverage `MCPSyncEngine` 100%
- [ ] 3.5.3 Tag `v1.1.0-beta` (MCP single-device)

## Phase 4: Remaining Adapters + Registry + Watcher (7-10 days)

### 4.1 Windsurf, Zed, Antigravity
- [ ] 4.1.1 `WindsurfAdapter.swift` + fixture + tests
- [ ] 4.1.2 `ZedAdapter.swift` + fixture + tests
- [ ] 4.1.3 `AntigravityAdapter.swift` + fixture + tests

### 4.2 Codex (TOML)
- [ ] 4.2.1 `MCP/Serializers/TOMLSerializer.swift` — minimal writer + reader, ≤ 200 LOC
- [ ] 4.2.2 `MCP/Serializers/TOMLSerializerTests.swift` — coverage 100%
- [ ] 4.2.3 `CodexAdapter.swift` + fixture + tests

### 4.3 JetBrains (XML)
- [ ] 4.3.1 `MCP/Serializers/XMLSerializer.swift` — XMLParser delegate
- [ ] 4.3.2 `MCP/Serializers/XMLSerializerTests.swift`
- [ ] 4.3.3 `JetBrainsAdapter.swift` — glob `~/Library/Application Support/JetBrains/*/options/mcp.xml`
- [ ] 4.3.4 Multi-IDE handling: sync vào tất cả IDE detect được; tests fixture với 2 IDE

### 4.4 Registry
- [ ] 4.4.1 `MCP/Registry/SmitheryClient.swift` — URLSession, retry với backoff
- [ ] 4.4.2 In-memory cache 10 phút
- [ ] 4.4.3 `MCP/Views/MCPRegistryView.swift` — search, list, install
- [ ] 4.4.4 "Install" button → tạo MCPServer trong bundle hiện tại; nếu server cần secret, prompt user nhập
- [ ] 4.4.5 Network failure → empty list + banner "Registry unavailable"
- [ ] 4.4.6 Tests với mock URLProtocol

### 4.5 File watcher
- [ ] 4.5.1 `MCP/Watcher/MCPFileWatcher.swift` — DispatchSource per configPath
- [ ] 4.5.2 Debounce 500ms
- [ ] 4.5.3 Combine subject publish events
- [ ] 4.5.4 UI subscribe trong `MCPClientsSyncView` → refresh badge "External change"
- [ ] 4.5.5 Setting `notifyExternalChanges` (mặc định true) → user notification
- [ ] 4.5.6 Suppress notification trong 5s sau lần ghi từ GreatDeploy
- [ ] 4.5.7 Cleanup fd trong `deinit`
- [ ] 4.5.8 Tests: tạo tmpdir, modify file, expect event trong 2s

### 4.6 Phase 4 acceptance
- [ ] 4.6.1 9/9 adapter pass fixture tests
- [ ] 4.6.2 Registry browse 7,300+ entry (verify manual)
- [ ] 4.6.3 File watcher detect external change trên cả 9 client (manual)
- [ ] 4.6.4 Tag `v1.2.0-beta`

## Phase 5: Multi-Device Sync (10-14 days)

### 5.1 Entitlements & Apple Developer setup
- [ ] 5.1.1 Tạo iCloud container `iCloud.com.tody-agent.greatdeploy` trong Apple Developer portal
- [ ] 5.1.2 Update `GreatDeploy.entitlements` với CloudKit và Ubiquity KVS
- [ ] 5.1.3 Document setup steps trong `docs/ICLOUD_SETUP.md`

### 5.2 Sync provider
- [ ] 5.2.1 `Sync/DeviceSyncProvider.swift` — protocol
- [ ] 5.2.2 `Sync/InMemorySyncProvider.swift` — fake provider cho test
- [ ] 5.2.3 `Sync/ICloudSyncProvider.swift` — implementation

### 5.3 Push flow
- [ ] 5.3.1 `MCPBundleStore.didChange` → debounce 30s → `provider.push`
- [ ] 5.3.2 NSUbiquitousKeyValueStore với key `mcpBundleIndex` = `[bundleId: ISO8601 timestamp]`
- [ ] 5.3.3 CloudKit CKRecord type `MCPBundle` field `payload: CKAsset`, `updatedAt: Date`, `deviceOrigin: String`
- [ ] 5.3.4 Payload JSON KHÔNG chứa secret value (verify với grep test)

### 5.4 Pull flow
- [ ] 5.4.1 CKQuerySubscription cho push notification
- [ ] 5.4.2 `provider.pull` query records updated since lastPullTimestamp
- [ ] 5.4.3 Decode JSON từ CKAsset
- [ ] 5.4.4 `ConflictResolver.merge(local, remote) -> [MCPBundle]`
- [ ] 5.4.5 Apply merged bundles vào `MCPBundleStore`

### 5.5 Conflict resolution
- [ ] 5.5.1 `Sync/ConflictResolver.swift` — per-server timestamp compare
- [ ] 5.5.2 Last-write-wins default
- [ ] 5.5.3 Identical content → no-op
- [ ] 5.5.4 Same timestamp diff content → flag conflict, keep local, surface UI
- [ ] 5.5.5 Tests 4 scenario

### 5.6 Missing secrets handling
- [ ] 5.6.1 Computed `MCPServer.missingSecretsOnThisDevice` (check Keychain entries có tồn tại không)
- [ ] 5.6.2 UI badge trong `MCPServersListView` và `MCPServerEditorView`
- [ ] 5.6.3 Sync workflow: skip secret injection cho server có missing secret, push warning
- [ ] 5.6.4 Tests

### 5.7 Settings UI
- [ ] 5.7.1 `MCP/Views/MultiDeviceSyncSettingsView.swift`
- [ ] 5.7.2 Toggle "Enable Multi-Device Sync" — opt-in, mặc định off
- [ ] 5.7.3 Hiển thị account iCloud hiện tại, last push/pull time
- [ ] 5.7.4 "Force Sync Now" button
- [ ] 5.7.5 "Reset and Re-pull from iCloud" — destructive, có confirmation

### 5.8 Tests
- [ ] 5.8.1 Unit test `ConflictResolver` 4 scenario
- [ ] 5.8.2 Integration test với InMemorySyncProvider: device A modify → device B pull → assert
- [ ] 5.8.3 Manual test trên 2 máy: tạo bundle máy A, verify máy B trong 60s
- [ ] 5.8.4 Manual test delete bundle máy A, verify máy B clean up
- [ ] 5.8.5 Manual test offline → online resync

### 5.9 Phase 5 acceptance
- [ ] 5.9.1 Push/pull < 60s end-to-end trong điều kiện mạng bình thường
- [ ] 5.9.2 0 secret value xuất hiện trong CloudKit payload (verified by inspection)
- [ ] 5.9.3 Conflict UI hoạt động trên scenario same-timestamp
- [ ] 5.9.4 Tag `v1.5.0-rc`

## Phase 6: Documentation, Release, Post-Release Hardening (5-7 days)

### 6.1 Docs
- [ ] 6.1.1 README.md — section "MCP Sync" với screenshot
- [ ] 6.1.2 README_vi.md và README_zh.md — dịch
- [ ] 6.1.3 `docs/MCP_SYNC.md` — chi tiết từng client config path, troubleshooting
- [ ] 6.1.4 `docs/MULTI_DEVICE_SYNC.md` — cách bật iCloud, FAQ về secret
- [ ] 6.1.5 CHANGELOG.md update
- [ ] 6.1.6 AGENTS.md cập nhật cấu trúc thư mục mới

### 6.2 Security audit
- [ ] 6.2.1 Chạy `reports/SECURITY_AUDIT_<date>.md` template
- [ ] 6.2.2 Grep token-like string trên toàn bộ artifact build + audit log
- [ ] 6.2.3 Verify mọi `Codable` MCP type không leak secret
- [ ] 6.2.4 Threat model cho multi-device sync (man-in-the-middle, account compromise)

### 6.3 Release
- [ ] 6.3.1 Bump version trong `project.yml` và `Info.plist`
- [ ] 6.3.2 Run release workflow `.github/workflows/release.yml`
- [ ] 6.3.3 Ad-hoc package qua `make package-ad-hoc` cho beta tester
- [ ] 6.3.4 Tag `v1.5.0` final
- [ ] 6.3.5 GitHub Release notes

### 6.4 Post-release watch
- [ ] 6.4.1 Theo dõi issue trong 2 tuần đầu
- [ ] 6.4.2 Hotfix branch nếu cần
- [ ] 6.4.3 Plan v2.0 (Linux/Windows port) trong change riêng

## Cross-Phase: Continuous Verification

- [ ] V.1 Mỗi phase merge: run `xcodebuild test`, build cả Debug và Release
- [ ] V.2 Mỗi phase: run security grep test trên build artifact + log
- [ ] V.3 Mỗi phase: smoke test "user chưa mở MCP tab thì app không tạo file/network"
- [ ] V.4 Performance: sync 9 client × 10 server < 2s mỗi release
```

---

## 📄 File 4: `openspec/changes/mcp-multi-platform-sync/upgrade_plan.md`

```markdown
# Upgrade Plan — MCP Multi-Platform / Multi-Device Sync

> Tài liệu này dành cho engineer triển khai. Nó không bàn về "tại sao"
> (xem proposal.md) hay "thiết kế kỹ thuật" (xem design.md), mà bàn
> về **thứ tự cụ thể cần code, branch nào, PR nào, gate gì**.

## Timeline tổng quan

| Phase | Tên | Effort | Ship as | Branch |
|---|---|---|---|---|
| 0 | Platform abstraction | 3-5d | internal | `change/mcp-phase0-platform` |
| 1 | MCP models + storage | 5-7d | internal | `change/mcp-phase1-models` |
| 2 | 4 core adapters | 10-14d | internal | `change/mcp-phase2-adapters-core` |
| 3 | Sync engine + UI | 7-10d | v1.1.0-beta | `change/mcp-phase3-engine-ui` |
| 4 | Remaining adapters + registry + watcher | 7-10d | v1.2.0-beta | `change/mcp-phase4-extras` |
| 5 | Multi-device sync | 10-14d | v1.5.0-rc | `change/mcp-phase5-multidevice` |
| 6 | Docs + release | 5-7d | v1.5.0 | `change/mcp-phase6-release` |

**Tổng**: 47-67 ngày làm việc cho 1 dev full-time, tương đương 10-14
tuần thực tế khi tính review và iteration. Mỗi phase là một PR
độc lập, có thể merge sequential vào `main` mà không phá branch
phase tiếp theo.

## Branching strategy

- `main` là always-shippable. Không bao giờ merge code half-done.
- Mỗi phase mở một branch từ `main`, làm xong, mở PR, review,
  squash-merge. Phase kế tiếp branch từ commit merge mới của `main`.
- KHÔNG dùng long-lived feature branch (`feature/mcp`) chứa tất cả
  phase. Lý do: nếu phase 3 ship beta và phase 4 đang dở, ta cần
  hotfix được phase 3 mà không kéo theo dở dang phase 4.

## Phase 0: Platform Abstraction (3-5 days)

**Mục tiêu duy nhất**: refactor pure. Code Swift hiện có đi qua
một protocol layer, không thay đổi hành vi, không thêm feature.

### Bước 1: Tạo protocol

Tạo `GreatDeploy/Platform/PlatformAdapter.swift` với protocol
`SecretStore`, `FileSystem`, `ProcessRunner`. Mỗi method khớp 1-1
với pattern đã dùng trong codebase. Ví dụ `SecretStore.read` khớp
với `KeychainService.readToken`.

### Bước 2: MacPlatform implementation

`Platform/MacPlatform.swift` chứa struct conform cả ba protocol.
Mỗi method gọi thẳng vào code hiện có. Không thay đổi semantic.

### Bước 3: Inject

Thay vì gọi `KeychainService.shared.readToken(...)`, callsite gọi
`Platform.current.secretStore.read(...)`. Singleton `Platform.current`
init từ `MacPlatform()` khi compile cho macOS.

### Bước 4: Stub Linux/Windows

`Platform/LinuxPlatform.swift.stub` và `WindowsPlatform.swift.stub`
chứa struct `fatalError("Not implemented in this release")` cho
mọi method. Wrapped trong `#if os(Linux)` / `#if os(Windows)`.
File `.stub` đảm bảo XcodeGen không include vào target macOS.

### Gate phase 0

PR merge khi và chỉ khi:
- Toàn bộ test suite hiện có (`xcodebuild test`) pass.
- Manual smoke: launch app, switch profile, verify behavior y hệt
  trước refactor.
- Code review: không có hành vi nào thay đổi, chỉ là forward.

## Phase 1: MCP Models + Storage (5-7 days)

**Mục tiêu**: data layer đầy đủ, không UI, không sync logic.

### Bước 1: Models

Implement 6 model file theo thứ tự (mỗi file < 200 LOC):
`TransportType` → `MCPClientKind` → `MCPServer` → `MCPBundle` →
`MCPSyncState` → `MCPSyncResult`.

`MCPServer.Codable` phải tuân thủ pattern security đã có trong
`DevProfile.Codable`. Lấy `DevProfile.swift` làm template, copy
struct `CodingKeys`, `init(from:)`, `encode(to:)`, `description`,
`debugDescription`.

### Bước 2: MCPBundleStore

`@MainActor ObservableObject` mirror pattern của `AccountStore`.
File `~/Library/Application Support/GreatDeploy/mcp-bundles.json`.
Atomic write qua `Platform.current.fileSystem.atomicWrite`.

### Bước 3: Keychain namespace

Thêm vào `KeychainService`:

```swift
private func mcpService(bundleId: UUID) -> String {
    "greatdeploy.mcp.\(bundleId.uuidString)"
}

private func mcpAccount(serverId: UUID, envKey: String) -> String {
    "\(serverId.uuidString).\(envKey)"
}

func saveMCPSecret(bundleId: UUID, serverId: UUID,
                   envKey: String, value: String) throws { ... }
// + read/delete
func deleteAllMCPSecrets(bundleId: UUID) throws { ... }
```

`deleteAllMCPSecrets` query với `kSecMatchSubjectContains` và

service prefix; iterate và delete từng entry.

### Bước 4: Migration

Trong `AccountStore.loadAccounts()`, sau khi load `profiles.json`,

gọi `migrateMCPBundleIdsIfNeeded()`. Hàm này:

1. Check nếu mọi profile đã có `mcpBundleId` → skip.
2. Backup `profiles.json` → `profiles.json.bak.<ISO8601>`. Nếu

   backup fail → abort migration, log error.
3. Với mỗi profile thiếu `mcpBundleId`, tạo bundle empty và gán id.
4. Atomic write `mcp-bundles.json` và `profiles.json`.

### Gate phase 1

* Coverage `MCP/Models/` ≥ 80%, `MCPBundleStore` 100%.
* Security test: encode `MCPServer` có secret env → JSON output

  không chứa giá trị secret (verified bằng test assertion regex).
* Smoke: launch app, không có file `mcp-bundles.json` được tạo

  cho đến khi user tạo bundle.

## Phase 2: Core Adapters (10-14 days)

 **Mục tiêu** : 4 adapter phổ biến nhất đọc/ghi/merge đúng. Chưa có

sync engine, chưa có UI.

### Thứ tự implement

Lý do thứ tự: Claude Desktop có schema đơn giản nhất, dùng làm

reference. Cursor và Claude Code CLI dùng cùng kiểu JSON với

key khác. VS Code phức tạp hơn vì có comments trong JSON

(JSONC) — cần xử lý careful.

1. `MCPClientAdapter` protocol và `JSONMerger` helper trước.

   `JSONMerger.merge(existing:managed:previouslySynced:) -> [String: Any]` là pure function, test 100%.
2. `ClaudeDesktopAdapter` — config path

   `~/Library/Application Support/Claude/claude_desktop_config.json`,

   key `mcpServers`, JSON chuẩn.
3. `CursorAdapter` — `~/.cursor/mcp.json`, key `mcpServers`.
4. `ClaudeCodeAdapter` — `~/.claude/settings.json`, key `mcpServers`

   nested trong settings, phải preserve mọi key khác.
5. `VSCodeAdapter` — JSONC: dùng `JSONSerialization` với option

   strip comment trước parse, nhưng khi write phải giữ comment

   nếu có. Phase 2 chấp nhận strip comment khi write (document

   trade-off); revisit nếu user feedback.

### Bộ fixture

Thu thập file config thật từ máy dev (anonymize: thay token bằng

`"REDACTED"`). Lưu trong `GreatDeployTests/Fixtures/mcp/<client>/`.

Mỗi client tối thiểu 3 fixture:

* `empty.json` — chưa có MCP server nào.
* `user_only.json` — chỉ có server user thêm.
* `mixed.json` — có cả server GreatDeploy-managed và user-added.

### Test scaffold

Helper `XCTAssertJSONEqual` so sánh JSON ignore key order.

Snapshot test: input fixture + managed + previouslySynced →

expected output JSON.

### Gate phase 2

* 4 adapter pass tất cả fixture test.
* Manual: trên máy dev có cài 4 client, chạy unit test rồi mở từng

  client, verify config vẫn parse được và list MCP server đúng.

## Phase 3: Sync Engine + UI (7-10 days)

 **Mục tiêu** : full sync workflow user-facing.

### Engine

Reference: copy structure `sync_to_client` từ

`apps/desktop/src-tauri/src/commands/sync.rs` của Conductor,

port sang Swift actor. Mỗi block trong Rust ⇄ một method trong

Swift; comment chỉ ra đoạn tương ứng để reviewer cross-check.

### SwitchEngine integration

`MCPSyncAdapter` conform `AdapterProtocol` (giả định change 004

đã merge — nếu chưa, mock một protocol minimal cho phase này và

mở change con kết nối thực sự sau).

### UI

Reference `AddEditAccountView.swift` cho form style. Reference

`HomeDashboardView.swift` cho list style. Reference Conductor

screenshot cho layout MCPClientsSyncView.

### Audit log

`~/Library/Logs/GreatDeploy/mcp-audit.log`. Format JSONL, mỗi dòng

một event:

```json
{"ts":"2026-...","event":"sync","client":"claude-desktop","ok":true,
 "servers":["fs","github"],"durationMs":234}
```

Tuyệt đối không log giá trị env. Test: sau khi run full test suite,

`grep -E '[A-Za-z0-9]{40,}' ~/Library/Logs/GreatDeploy/*.log` phải

trả 0 dòng.

### Gate phase 3

* End-to-end test trên máy thật: 3 server × 4 client.
* Fail-injection test: rollback byte-for-byte.
* Tag `v1.1.0-beta`, ship ad-hoc DMG cho 5 beta tester.

## Phase 4: Remaining Adapters + Registry + Watcher (7-10 days)

 **Mục tiêu** : feature parity với Conductor (9 adapter, registry,

watcher).

### TOML mini library

Subset đủ dùng: top-level table, nested table dùng `[a.b.c]`

syntax, string value với escape, array of string, array of inline

table. Test với fixture Codex thật. Bench: parse + serialize 50KB

trong < 50ms.

### XML mini library

`XMLParser` delegate-based, viết wrapper SAX → mini DOM tree.

Test với fixture JetBrains.

### JetBrains multi-IDE

Glob `~/Library/Application Support/JetBrains/*/options/mcp.xml`.

Filter các thư mục có pattern `IntelliJIdea*`, `PyCharm*`, etc.

Sync vào TẤT CẢ. UI hiển thị 1 entry “JetBrains” với count “N

IDEs detected”.

### Smithery client

Endpoint cần verify trong implementation (Conductor codebase có

sẵn URL chính xác — check `apps/desktop/src-tauri/src/commands/registry.rs`).

Nếu API có rate limit, retry với backoff 1s, 2s, 4s.

### File watcher

DispatchSource per file descriptor. Quan trọng: phải mở fd dạng

`O_EVTONLY` để không khoá file cho process khác. Cleanup trong

`deinit` và khi user disable trong settings.

Suppress notification trong 5s sau lần ghi của GreatDeploy:

maintain timestamp `lastSelfWriteAt` per client; nếu event đến

trong 5s sau timestamp, ignore.

### Gate phase 4

* 9/9 adapter pass fixture.
* Registry browse hoạt động trên live API.
* Watcher detect external change ≤ 2s.
* Tag `v1.2.0-beta`.

## Phase 5: Multi-Device Sync (10-14 days)

 **Mục tiêu** : bundle metadata sync qua iCloud; secret KHÔNG sync.

### Apple Developer setup

Một dev (chủ Apple Developer account) phải:

1. Tạo iCloud container `iCloud.com.tody-agent.greatdeploy`.
2. Update entitlements file.
3. Document trong `docs/ICLOUD_SETUP.md`.

Trong khi chờ setup, dùng `InMemorySyncProvider` để dev và test.

### CloudKit schema

Record type `MCPBundle`:

* `payload` (CKAsset): JSON file chứa toàn bộ bundle (không

  secret).
* `updatedAt` (Date): cho ConflictResolver.
* `deviceOrigin` (String): UUID máy push.
* recordName = bundleId.uuidString.

Subscription: `CKQuerySubscription` với predicate `TRUEPREDICATE`

và options `[.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]`. Notification chỉ silent (không show user

banner) — app handle in background.

### Push debounce

User edit bundle → `MCPBundleStore.didChange` Combine signal →

debounce 30s → `provider.push(changedBundles)`. Lý do 30s: tránh

flap khi user edit nhanh nhiều lần.

### Pull flow

Notification arrive → call `pull()` → query records `WHERE updatedAt > lastPullTimestamp` → decode JSON → `ConflictResolver. merge` → apply.

### Conflict UI

Trong `MCPServerEditorView`, nếu `MCPSyncState.hasConflict(serverId)`,

hiển thị banner cảnh báo với 2 button “Use Local” / “Use Remote”,

và một button “View Diff” mở sheet so sánh field-by-field.

### Missing secret UX

Trong `MCPServersListView`, server có

`missingSecretsOnThisDevice == true` hiển thị badge “🔑 Add

secret” thay vì badge “Synced”. Click → mở

`MCPServerEditorView` với cursor focus vào field secret đầu tiên.

### Gate phase 5

* 2-device manual test: A modify → B see trong 60s.
* 2-device manual test: A delete → B clean up trong 60s.
* CloudKit payload không chứa secret (manual inspection bằng

  CloudKit Dashboard).
* Tag `v1.5.0-rc1`.

## Phase 6: Docs + Release (5-7 days)

### Tài liệu

`docs/MCP_SYNC.md` cần có ít nhất:

* Bảng config path cho 9 client.
* Workflow điển hình.
* Troubleshooting: client không detect, sync verify fail, watcher

  không bắt event, registry timeout.
* Security note: secret nằm đâu, không sync qua iCloud.

`docs/MULTI_DEVICE_SYNC.md` cần có:

* Cách enable.
* Yêu cầu iCloud Drive bật.
* FAQ: vì sao phải nhập lại secret trên máy mới? Conflict resolve

  thế nào? Disable sync có xoá data không?

### Release

Bump version `1.5.0` trong `project.yml`, `Info.plist`, README.

Chạy `release.yml` workflow (đã có sẵn trong repo). Ad-hoc package

qua `make package-ad-hoc` cho beta tester.

GitHub Release notes phải mention:

* Major: MCP sync 9 client.
* Major: multi-device qua iCloud.
* Bảng so sánh với Conductor (credit Conductor).
* Migration path (auto, không cần user action).

### Post-release watch

2 tuần đầu, theo dõi GitHub issue tag `mcp` và `multi-device`.

Hotfix branch `hotfix/v1.5.x` nếu cần. Sau 2 tuần stable, mở

proposal `008-linux-windows-port` (change riêng, không thuộc plan

này).

## Risk-driven detours

Nếu trong khi triển khai phát hiện một trong các risk dưới,  **dừng

phase hiện tại và xử lý trước** :

| Trigger                                                | Action                                                             |
| ------------------------------------------------------ | ------------------------------------------------------------------ |
| Bất kỳ fixture nào leak secret qua JSON encode      | Stop, fix `Codable`ngay, không advance phase                    |
| File watcher leak file descriptor (kiểm tra `lsof`) | Stop, fix cleanup, không advance phase                            |
| Migration phá `profiles.json`của một user test    | Rollback ngay, abort phase 1, thiết kế lại                      |
| CloudKit reject schema                                 | Đổi sang JSON-as-string thay vì CKAsset, đánh đổi 1MB limit |
| Smithery API thay đổi format                         | Switch sang fallback hardcoded popular list, mở issue upstream    |
| Coverage `MCPSyncEngine`< 100%                       | Block PR phase 3, không merge                                     |

## Definition of Done (cho cả change)

Change này coi như xong khi:

1. Mọi acceptance criterion trong `proposal.md` xanh.
2. Mọi task trong `tasks.md` checked.
3. Có một release `v1.5.0` notarized DMG.
4. Documentation đầy đủ.
5. Beta tester (≥ 5) confirm sync hoạt động trên ≥ 2 máy thật của

   họ.
6. 2 tuần post-release không có critical bug.
7. Security audit report `reports/SECURITY_AUDIT_<date>.md` đánh

   giá “no critical, no high” issue.
8. PR archive vào `openspec/changes/archive/<date>-mcp-multi-platform-sync/`.

```

---

## 📄 File 5: `openspec/changes/mcp-multi-platform-sync/specs/mcp-sync.md`

```markdown
# Capability Spec — MCP Sync

> Đây là delta spec cho capability MỚI `mcp-sync`. Khi change này
> được archive, file này được copy vào
> `openspec/specs/mcp-sync/spec.md` và trở thành nguồn duy nhất
> mô tả capability đang ship trên main.

## ADDED Requirements

### Requirement: Manage MCP server bundles

The system SHALL provide CRUD operations for `MCPBundle` entities
that contain one or more `MCPServer` records.

#### Scenario: Create empty bundle
- GIVEN no bundle exists
- WHEN user creates a new bundle with name "Personal"
- THEN `mcp-bundles.json` is written with one bundle entry
- AND no Keychain entry is created
- AND no network call is made

#### Scenario: Add server with secret env to bundle
- GIVEN a bundle "Personal" exists
- WHEN user adds a server with `command=npx`, `args=["-y","github-mcp"]`,
  `env={"GITHUB_TOKEN":"ghp_xxx"}`, `secretEnvKeys=["GITHUB_TOKEN"]`
- THEN the server is appended to bundle's `servers` array
- AND `mcp-bundles.json` is rewritten WITHOUT the value `"ghp_xxx"`
- AND a Keychain entry under service `greatdeploy.mcp.<bundleId>`,
  account `<serverId>.GITHUB_TOKEN`, value `"ghp_xxx"` is created
- AND `grep ghp_xxx ~/Library/Application\ Support/GreatDeploy/`
  returns 0 lines

#### Scenario: Delete bundle removes all secrets
- GIVEN a bundle with 3 servers, each having 2 secret env keys
- WHEN user deletes the bundle
- THEN all 6 Keychain entries under `greatdeploy.mcp.<bundleId>.*` are removed
- AND the bundle is removed from `mcp-bundles.json`
- AND any `DevProfile` referencing this bundle has `mcpBundleId` set to `nil`

### Requirement: Detect installed MCP clients

The system SHALL detect which of the 9 supported MCP clients are
installed on the current device.

#### Scenario: Detect when client config directory exists
- GIVEN `~/.cursor/` exists
- WHEN `CursorAdapter.detect()` is called
- THEN it returns `true`
- AND the result is shown as "Detected" in `MCPClientsSyncView`

#### Scenario: Detect when only config file exists
- GIVEN `~/Library/Application Support/Claude/claude_desktop_config.json` exists
- WHEN `ClaudeDesktopAdapter.detect()` is called
- THEN it returns `true`

#### Scenario: Skip undetected clients during sync
- GIVEN `~/.codex/` does NOT exist
- WHEN user clicks "Sync All"
- THEN `CodexAdapter.writeServers` is NOT called
- AND `MCPSyncResult` for codex shows `success=true, serversWritten=0`

### Requirement: Sync bundle to clients atomically per client

The system SHALL sync an `MCPBundle` to one or more `MCPClientKind`s
with snapshot, verify, and rollback semantics per client.

#### Scenario: Successful sync to Claude Desktop
- GIVEN a detected Claude Desktop with existing config containing
  user-added server "filesystem"
- AND a bundle with managed servers "github" and "postgres"
- WHEN sync is invoked for Claude Desktop
- THEN the config now contains "filesystem", "github", "postgres"
- AND `MCPSyncState[claudeDesktop].previouslySyncedNames` contains
  `{"github", "postgres"}`
- AND `MCPSyncState[claudeDesktop].lastSyncedAt` is set

#### Scenario: Orphan cleanup on subsequent sync
- GIVEN previous sync wrote `{"github", "postgres"}` and
  `previouslySyncedNames = {"github", "postgres"}`
- AND user removed "postgres" from bundle
- WHEN sync is invoked again
- THEN client config contains "filesystem" and "github" but NOT "postgres"
- AND "filesystem" (user-added, never in previouslySyncedNames) is preserved
- AND `previouslySyncedNames` still equals `{"github", "postgres"}` (cumulative)

#### Scenario: Verify-after-write rollback
- GIVEN a fault injection causes `writeServers` to write garbled JSON
- WHEN sync is invoked
- THEN `readServers` after write fails to find managed server names
- AND the engine atomic-writes the captured `existingContent` back
- AND the result is `success=false` with non-empty `error`
- AND the audit log contains an "error" entry
- AND the original config file is byte-for-byte identical to pre-sync

#### Scenario: Secret injection from Keychain
- GIVEN a server has `env={"GITHUB_TOKEN":""}` and
  `secretEnvKeys=["GITHUB_TOKEN"]`
- AND Keychain entry for this server's GITHUB_TOKEN contains `"ghp_xxx"`
- WHEN sync is invoked
- THEN the written client config has `env.GITHUB_TOKEN == "ghp_xxx"`
- AND in-memory `MCPServer.env` reverts to empty after sync (no caching)

#### Scenario: Missing secret on this device produces warning, not failure
- GIVEN a server has `secretEnvKeys=["API_KEY"]`
- AND no Keychain entry exists for this server's API_KEY on this device
- WHEN sync is invoked
- THEN the server is still written to client config with `env.API_KEY` absent
- AND `MCPSyncResult.warnings` contains "Server '<name>': missing secret API_KEY"
- AND `success=true`

### Requirement: Detect external config changes

The system SHALL watch each detected client's config file and
notify when external changes occur.

#### Scenario: External edit triggers detection refresh
- GIVEN MCPFileWatcher is observing Cursor's config
- WHEN user edits `~/.cursor/mcp.json` with `vim`
- THEN within 2 seconds, `MCPClientsSyncView` shows "External change" badge
- AND if `notifyExternalChanges == true`, a user notification appears

#### Scenario: Suppress self-write notification
- GIVEN GreatDeploy just wrote to `~/.cursor/mcp.json` 3 seconds ago
- WHEN the watcher fires for this file
- THEN no notification is shown
- AND no "External change" badge appears

### Requirement: Browse and install from registry

The system SHALL allow users to browse the Smithery MCP server
registry and install a server into the current bundle.

#### Scenario: Browse registry online
- GIVEN network connectivity is available
- WHEN user opens `MCPRegistryView` and searches "filesystem"
- THEN `SmitheryClient.search("filesystem")` is called
- AND matching entries are displayed
- AND each entry shows name, description, install count

#### Scenario: Install registry server into bundle
- GIVEN a registry entry "github-mcp" requires `GITHUB_TOKEN` secret env
- WHEN user clicks "Install to current bundle"
- THEN a new `MCPServer` is created in the active bundle
- AND `MCPServerEditorView` opens with the GITHUB_TOKEN field highlighted
- AND the server is NOT synced to clients until user clicks Sync

#### Scenario: Registry unavailable falls back gracefully
- GIVEN network is offline
- WHEN user opens `MCPRegistryView`
- THEN a banner "Registry unavailable, check connection" is shown
- AND no app crash, no infinite spinner

### Requirement: Multi-device sync of bundle metadata

The system SHALL synchronize `MCPBundle` metadata (NOT secrets)
across the user's devices that are signed into the same iCloud
account.

#### Scenario: Push on local change
- GIVEN multi-device sync is enabled
- WHEN user modifies a bundle on device A
- THEN within 30 seconds, the bundle's record in CloudKit
  `privateCloudDatabase` is updated
- AND `NSUbiquitousKeyValueStore`'s `mcpBundleIndex` reflects the
  new `updatedAt`

#### Scenario: Pull on remote change
- GIVEN device A pushed a bundle update
- AND device B has multi-device sync enabled and is online
- WHEN CloudKit push notification arrives at device B
- THEN within 30 seconds of receipt, the bundle on device B is
  updated to match device A's version
- AND any server with `secretEnvKeys` that has no matching Keychain
  entry on device B shows badge "🔑 Add secret"

#### Scenario: Secret never leaves device
- GIVEN a bundle has a server with `secretEnvKeys=["TOKEN"]` and
  Keychain entry on device A containing "abc123"
- WHEN device A pushes the bundle to CloudKit
- THEN the `CKAsset` payload's JSON has the TOKEN env value as empty
  or absent
- AND `"abc123"` does not appear anywhere in the CloudKit record
- AND no Keychain replication happens

#### Scenario: Conflict on same-timestamp divergent edits
- GIVEN device A and device B both edited the same server's `command`
  field at exactly the same second
- AND their content differs
- WHEN sync completes on device B
- THEN device B keeps its local version
- AND a "Conflict" banner is shown in `MCPServerEditorView` for that
  server
- AND user can resolve with "Use Local" / "Use Remote" / "View Diff"

### Requirement: Migrate existing profiles to bundle model

The system SHALL automatically migrate existing `DevProfile`
records to reference an `MCPBundle` (empty by default) without
losing user data.

#### Scenario: First launch after upgrade
- GIVEN `profiles.json` exists with 3 profiles, none having `mcpBundleId`
- AND `mcp-bundles.json` does not exist
- WHEN app launches
- THEN `profiles.json.bak.<timestamp>` is created with identical content
- AND `mcp-bundles.json` is created with 3 empty bundles, one per profile
- AND `profiles.json` is rewritten with each profile referencing its
  new `mcpBundleId`
- AND user secrets (PATs, Cloudflare tokens) in Keychain are untouched

#### Scenario: Migration idempotency
- GIVEN migration already ran (all profiles have `mcpBundleId`)
- WHEN app launches again
- THEN no migration runs
- AND no new `.bak` file is created

#### Scenario: Migration aborts safely on backup failure
- GIVEN disk is full and backup cannot be written
- WHEN migration runs
- THEN no changes are made to `profiles.json` or Keychain
- AND error is logged
- AND user sees a non-blocking warning banner

## MODIFIED Requirements

### Requirement: Switch profile applies all configured adapters

> Modified from change 004 (`atomic-switch-engine`).

The switch engine SHALL include `MCPSyncAdapter` as the last
adapter in the ordered list (after Cloudflare), and its snapshot/
revert mechanism SHALL participate in the transactional switch.

#### Scenario: Switch profile syncs its MCP bundle
- GIVEN profile "Work" has `mcpBundleId` pointing to bundle "Work MCP"
- WHEN user switches to profile "Work"
- THEN GitHub adapter applies first
- AND Cloudflare adapter applies second
- AND `MCPSyncAdapter` applies third, syncing "Work MCP" to all
  enabled clients in the bundle's `enabledClients`
- AND if any of the three adapters fails, ALL applied adapters
  revert via their `snapshot`s

#### Scenario: Profile without MCP bundle skips MCP step
- GIVEN profile "Personal" has `mcpBundleId == nil`
- WHEN user switches to profile "Personal"
- THEN `MCPSyncAdapter` is invoked but is a no-op
- AND switch completes normally

## Non-Functional Requirements

### Performance
- Sync to 9 clients with 10 servers each: end-to-end < 2 seconds
  on reference machine (M2 MBA, macOS 14).
- File watcher event-to-UI-refresh latency: < 2 seconds.
- Multi-device sync push-to-remote-pull: < 60 seconds in normal
  network conditions.

### Security
- 0 plaintext secret values in `mcp-bundles.json` (verified by
  test).
- 0 plaintext secret values in `~/Library/Logs/GreatDeploy/*.log`
  (verified by grep).
- 0 plaintext secret values in any CloudKit record payload
  (verified by manual CloudKit Dashboard inspection).
- Secret Keychain entries namespaced under
  `greatdeploy.mcp.<bundleId>.<serverId>.<envKey>`.
- Bundle deletion bulk-removes all namespaced Keychain entries
  with no residual.

### Reliability
- All file writes atomic via `.tmp` + `rename`.
- All file writes preceded by timestamped `.bak` backup; backups
  pruned according to `backupRetention` setting (default 30 days).
- Sync verify-after-write detects corrupted writes; rollback
  byte-for-byte to captured pre-sync content.

### Observability
- Audit log JSONL at `~/Library/Logs/GreatDeploy/mcp-audit.log`.
- Per-sync entry contains: timestamp, client, success, server
  names (NOT env values), duration ms, warnings.
- About panel shows "Last MCP sync" with timestamp and outcome.

### Compatibility
- macOS 13.0 (Ventura) and later — same baseline as today.
- Decoder forward-compatible: future fields use
  `decodeIfPresent` so older builds don't crash on newer JSON.
- Decoder backward-compatible: pre-MCP `profiles.json` (no
  `mcpBundleId` field) loads cleanly.
```

---

## Tóm tắt cách dùng

Tạo cấu trúc thư mục trong repo bạn:

```
openspec/changes/mcp-multi-platform-sync/
├── proposal.md          (File 1)
├── design.md            (File 2)
├── tasks.md             (File 3)
├── upgrade_plan.md      (File 4)
└── specs/
    └── mcp-sync.md      (File 5)
```

Sau đó:

1. `git checkout -b change/mcp-multi-platform-sync-proposal`
2. Paste 5 file trên vào đúng đường dẫn.
3. Commit: `docs(openspec): propose mcp-multi-platform-sync change`
4. Mở PR.
5. Sau khi review và approve, bắt đầu `change/mcp-phase0-platform` theo `upgrade_plan.md`.

Cấu trúc này theo đúng convention đã thấy trong `openspec/changes/security-fix/` của repo: bốn file gốc (proposal/design/tasks/upgrade_plan) cộng thêm thư mục `specs/` để chứa delta capability spec — đây là pattern OpenSpec chuẩn cho phép khi archive change thì spec sẽ promote thẳng vào `openspec/specs/mcp-sync/spec.md` thành nguồn duy nhất mô tả capability đang sống trên main.

Nếu bạn muốn, bước tiếp theo tôi có thể viết ngay (a) Swift skeleton code cho `PlatformAdapter` + `MacPlatform` của Phase 0 để bạn paste vào và bắt đầu, hoặc (b) skeleton cho `MCPServer`, `MCPBundle`, `MCPClientAdapter` của Phase 1-2 — báo tôi hướng bạn muốn đi.

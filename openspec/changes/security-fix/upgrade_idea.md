
# 📋 Dự án: **DevProfileBar** (tên gợi ý)

> *Native macOS menu bar app để quản lý & switch unified profiles: GitHub + Cloudflare (+ mở rộng), giúp tránh push nhầm account.*

## 1. Mục tiêu & Vấn đề giải quyết

**Pain points hiện tại:**

* Switch tài khoản GitHub/Cloudflare phải sửa nhiều nơi: git config, SSH, Keychain, wrangler config, env vars…
* Push code nhầm sang repo công ty bằng account cá nhân (hoặc ngược lại) → khó rollback, lộ bí mật
* Cloudflare CLI/Wrangler chỉ login 1 account/lần, switch rất phiền
* Không có cảnh báo trực quan “mình đang ở account nào”

**Mục tiêu sản phẩm:**

* 1 click switch toàn bộ context (GitHub + Cloudflare) theo **Profile** (Personal / Company A / Project X)
* Hiển thị rõ ràng active profile trên menubar (icon + màu + tên ngắn)
* **Pre-push guard** : cảnh báo trước khi commit/push nếu repo và profile không khớp
* Lưu trữ an toàn (Keychain), không bao giờ commit credentials

## 2. Khái niệm Profile

Một **Profile** là một bundle context gồm:

```
Profile "Company-A"
├── GitHub
│   ├── username, email
│   ├── PAT / SSH key path
│   └── git config (user.name, user.email, signingkey)
├── Cloudflare
│   ├── API Token
│   ├── Account ID
│   └── Default zone (optional)
├── Scope rules (optional)
│   ├── Allowed repo paths: ~/work/company-a/**
│   └── Allowed git remotes: github.com/company-a/*
└── Metadata: color, icon, tag
```

## 3. Kiến trúc kỹ thuật

**Tech stack:**

* **Ngôn ngữ** : Swift + SwiftUI (native, nhẹ, đúng style của 2 repo tham khảo)
* **Min OS** : macOS 13 Ventura+
* **Lưu trữ secrets** : macOS Keychain Services (API tokens, PATs)
* **Lưu trữ config** : `~/Library/Application Support/DevProfileBar/profiles.json` (chỉ metadata, không có secret)
* **CLI companion** (optional): `devprofile` binary để dùng trong shell hook

**Module chính:**

| Module                  | Chức năng                                                                |
| ----------------------- | -------------------------------------------------------------------------- |
| `MenuBarController`   | UI menu bar, dropdown switcher, indicator                                  |
| `ProfileStore`        | CRUD profile, JSON persistence                                             |
| `KeychainManager`     | Lưu/đọc secrets an toàn                                                |
| `GitHubAdapter`       | Update `~/.gitconfig`, SSH config, Keychain entry `https://github.com` |
| `CloudflareAdapter`   | Update wrangler config +`CLOUDFLARE_API_TOKEN`via `launchctl setenv`   |
| `ScopeGuard`          | Theo dõi `cwd`/ git repo hiện tại, cảnh báo mismatch                |
| `ShellHook`(optional) | Inject vào shell prompt để hiện active profile                         |

## 4. Tính năng theo Phase

### **Phase 1 — MVP (2-3 tuần)**

Mục tiêu: switch được GitHub + Cloudflare từ menubar, không có guard.

* Tạo/sửa/xóa profile qua UI Settings
* Lưu API token Cloudflare + GitHub PAT vào Keychain
* Khi click “Switch to Profile X”:
  * Ghi đè global `~/.gitconfig` ([user.name](http://user.name/), user.email)
  * Update Keychain internet password cho `github.com`
  * Update wrangler config file (`~/.wrangler/config/default.toml`)
  * `launchctl setenv CLOUDFLARE_API_TOKEN <token>` (để GUI apps đọc được)
* Menubar hiển thị: icon + tên profile + dot màu
* Test scenario: push được vào đúng repo, `wrangler whoami` đúng account

### **Phase 2 — Safety & UX (1-2 tuần)**

Mục tiêu: chống push nhầm.

* **Scope rules** : gán mỗi profile một list path/remote regex
* **Pre-push git hook** (auto-install global): check active profile khớp với remote URL không, nếu không → block + thông báo
* **Repo detector** : khi user `cd` vào project, app detect và nếu profile sai → notification “⚠️ You’re in `~/work/abc` but active profile is `Personal`. Switch?”
* Onboarding wizard: import từ existing `~/.gitconfig` và `wrangler whoami`
* Quick action: phím tắt global (e.g. `⌘⇧P`) mở switcher

### **Phase 3 — Mở rộng (sau khi MVP ổn)**

* Thêm adapter cho:  **AWS profiles** ,  **npm registry token** ,  **SSH key chain** ,  **kubectl context** ,  **Docker Hub** , **Vercel**
* Tổng hợp: 1 profile = 1 “developer identity” hoàn chỉnh
* Auto-switch: tự đổi profile theo working directory (giống `direnv`)
* Sync profiles giữa nhiều máy qua iCloud (chỉ metadata, secrets vẫn local)

### **Phase 4 — Distribution**

* Homebrew cask: `brew install --cask devprofilebar`
* Sparkle framework cho auto-update
* Notarize + sign với Apple Developer ID
* Mã nguồn mở MIT trên GitHub

## 5. Cấu trúc Repo đề xuất

```
DevProfileBar/
├── App/                          # SwiftUI app entry
│   ├── DevProfileBarApp.swift
│   └── MenuBarView.swift
├── Core/
│   ├── Profile.swift             # Model
│   ├── ProfileStore.swift
│   └── KeychainManager.swift
├── Adapters/
│   ├── GitHubAdapter.swift
│   ├── CloudflareAdapter.swift
│   └── AdapterProtocol.swift     # cho mở rộng
├── Safety/
│   ├── ScopeGuard.swift
│   └── GitHookInstaller.swift
├── UI/
│   ├── ProfileEditor.swift
│   ├── SwitcherPopup.swift
│   └── OnboardingWizard.swift
├── Hooks/
│   └── pre-push.sh               # git hook template
├── CLI/                          # optional companion
│   └── devprofile.swift
└── README.md
```

## 6. Roadmap timeline gợi ý

| Tuần | Việc                                                                    |
| ----- | ------------------------------------------------------------------------ |
| 1     | Setup project Swift, ProfileStore + KeychainManager, UI menubar cơ bản |
| 2     | GitHubAdapter + CloudflareAdapter, switch end-to-end                     |
| 3     | UI Settings (CRUD profile), onboarding, polish —**release v0.1**  |
| 4-5   | ScopeGuard + git hook + notifications —**release v0.2**           |
| 6+    | Adapter mới + Homebrew distribution —**release v1.0**            |

## 7. Rủi ro & Lưu ý kỹ thuật

* **Keychain ACL** : cần xử lý case user phải approve mỗi lần app đọc, có thể dùng `kSecAttrAccessGroup` để tránh prompt liên tục.
* **Wrangler OAuth vs API Token** : như doc của CloudflareStatusBar đã nêu, OAuth token (`wrangler login`) và API token loại trừ nhau — app nên ưu tiên API token mode.
* **launchctl setenv** chỉ ảnh hưởng processes start sau khi set — terminal đang mở sẽ không thấy biến mới. Cần thông báo user hoặc cung cấp shell hook.
* **Git config global vs local** : nên cho user chọn mode “always global” hoặc “per-repo” (an toàn hơn nhưng phức tạp).
* **Bảo mật** : KHÔNG bao giờ log token, không gửi telemetry mặc định.

## 8. Bước tiếp theo cho bạn

1. **Validate ý tưởng** : bạn chốt với mình — Phase 1 đã đủ giải quyết pain của bạn chưa? Có muốn thêm gì vào MVP?
2. **Chọn approach** : tự code từ đầu, hay fork `GitAccountSwitcher` của MinhOmega rồi thêm Cloudflare module vào? (fork sẽ nhanh hơn 2-3 tuần)
3. **Đặt tên & tạo repo** : mình gợi ý `DevProfileBar`, `ProfileSwitch`, hoặc `ContextBar` — bạn thích tên nào?

Bạn muốn mình đi sâu phần nào trước — thiết kế UI mockup, viết code skeleton Swift cho Phase 1, hay chi tiết kỹ thuật phần git hook chống push nhầm?

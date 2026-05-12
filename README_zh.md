# Great Deploy

<p align="center">
  <img src="Assets/GreatDeploy_GitHub_Thumbnail.png" alt="Great Deploy Thumbnail" width="100%">
</p>

<p align="center">
  <a href="README.md">English</a> | <a href="README_vi.md">Tiếng Việt</a> | <a href="README_zh.md">中文</a>
</p>

<p align="center">
  <strong>一款原生的 macOS 菜单栏应用程序，可无缝切换多个开发者配置文件（GitHub + Cloudflare）</strong>
</p>

<p align="center">
  <a href="#功能">功能</a> |
  <a href="#安装">安装</a> |
  <a href="#使用方法">使用方法</a> |
  <a href="#工作原理">工作原理</a> |
  <a href="#故障排除">故障排除</a>
</p>

---

## 🛑 痛点问题

在多个开发者身份之间来回切换令人头疼。无论您是在**个人**、**工作**或**客户**的 GitHub 账号之间切换，手动更新您的 `git config`，管理不同的个人访问令牌（PAT），以及替换 Cloudflare 凭证都需要花费时间，且常常导致用错账号进行了尴尬的错误提交（Commit）。

## 🚀 解决方案

**Great Deploy** 是您的一键式环境切换神器。它安静地驻留在您的 macOS 菜单栏中，让您能够即时切换整个开发环境。

只需单击一下，Great Deploy 就会：
1. 在 macOS 的 Keychain 中安全地替换您的 GitHub 凭证。
2. 更新全局的 `git config user.name` 和 `user.email`。
3. 将正确的 Cloudflare API 令牌注入您的 `~/.wrangler/config/default.toml` 和 macOS `launchctl` 环境中。

再也不用在终端里折腾命令了。彻底告别用错账号提交代码的尴尬。

## 功能

- **菜单栏界面** - 驻留在菜单栏中，以便即时访问
- **一键切换** - 只需一键即可切换开发者配置文件（GitHub + Cloudflare）
- **Keychain 整合** - 在 macOS Keychain 中安全地自动更新凭证
- **Git 配置管理** - 更新 `git config --global user.name` 和 `user.email`
- **Cloudflare 整合** - 管理 `~/.wrangler/config/default.toml` 和 launchctl 环境中的 `CLOUDFLARE_API_TOKEN` 与 `CLOUDFLARE_ACCOUNT_ID`
- **安全存储** - PAT 和 API 令牌安全存储于 Keychain 中（绝文明文保存）
- **登录时启动** - 可选择在登录时自动启动
- **原生系统通知** - 账号切换完成后获取通知
- **无 Dock 图标** - 作为后台实用程序运行（仅限菜单栏）
- **支持深色模式** - 自动跟随系统外观

## 系统要求

- **macOS 13.0** (Ventura) 及更高版本
- **Xcode 15.0** 及更高版本 (用于源码编译)
- 已安装 **Git** (通常位于 `/usr/bin/git` 或通过 Homebrew 安装)
- **Wrangler / Cloudflare CLI** (可选，用于部署 Cloudflare)

## 安装

### 选项 1：通过终端编译 (推荐)

```bash
# 克隆仓库
git clone https://github.com/MinhOmega/GreatDeploy.git
cd GreatDeploy/GreatDeploy

# 一键清理、编译并安装
xcodebuild -project GreatDeploy.xcodeproj -scheme GreatDeploy clean && \
rm -rf ~/Library/Developer/Xcode/DerivedData/GreatDeploy-* && \
xcodebuild -project GreatDeploy.xcodeproj -scheme GreatDeploy -configuration Release build && \
rm -rf /Applications/GreatDeploy.app && \
cp -R ~/Library/Developer/Xcode/DerivedData/GreatDeploy-*/Build/Products/Release/GreatDeploy.app /Applications/ && \
open /Applications/GreatDeploy.app
```

### 选项 2：通过 Xcode 编译

1. 在 Xcode 中打开 `GreatDeploy.xcodeproj`。
2. 在 Project Settings > Signing & Capabilities 中选择您的 **Development Team**。
3. 选择 **Product > Archive** (用于正式发布构建)，或按 **Cmd+R** 进行编译并运行。

## 使用方法

1. 点击菜单栏图标，然后选择 **"Add Account"** (或加号 **+** 按钮)。
2. 填写配置文件详细信息 (显示名称、GitHub 用户名、个人访问令牌、Git 名称、Git 邮箱，以及可选的 Cloudflare 信息)。
3. 添加后，您可以直接从菜单栏点击任何账号，Great Deploy 将立即更改相应的 Git 配置和 Keychain。

## 如何创建个人访问令牌 (PAT)

1. 前往 [GitHub Settings > Developer settings > Personal access tokens](https://github.com/settings/tokens)。
2. 生成新的 Token (Fine-grained 细粒度或 Classic 经典版)。
   - 经典版：勾选 `repo`, `read:user`, `user:email` 权限。
   - 细粒度版：选择针对 Contents 和 Metadata 的读/写权限。
3. 复制 Token (您将只能看到一次) 并将其粘贴到 Great Deploy 中。

## 安全性

Great Deploy **不支持沙盒模式 (Not Sandboxed)**，因为应用程序需要完整的 Keychain 访问权限、通过 Shell 执行 `git` 命令以及读写 `~/.gitconfig` 文件的权限，这些均与 Apple App Store 的默认沙盒机制不兼容。

- Token 在 macOS Keychain 中受到加密保护。
- Token 绝不会以明文形式记录或存储在 UserDefaults 中。
- 每个账号的 Token 分别存储在独立的 Keychain 条目中。

## 致谢

- **特别鸣谢**：Great Deploy 是针对最初的 **GitAccountSwitcher** 应用程序进行全面升级和扩展的版本。我们真诚地感谢原作者 (包括 MinhOmega) 提供的开源基础及其在 Keychain 整合方面的优秀理念，才使得这款工具的诞生成为可能。

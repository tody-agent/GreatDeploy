# Great Deploy

<p align="center">
  <img src="docs/icon.png" alt="Great Deploy Icon" width="128" height="128">
</p>

<p align="center">
  <strong>A native macOS menu bar app for seamlessly switching between multiple developer profiles (GitHub + Cloudflare)</strong>
</p>

<p align="center">
  <a href="#features">Features</a> |
  <a href="#installation">Installation</a> |
  <a href="#usage">Usage</a> |
  <a href="#how-it-works">How It Works</a> |
  <a href="#troubleshooting">Troubleshooting</a>
</p>

---

## Features

- **Menu Bar Interface** - Lives in your menu bar for instant access
- **One-Click Switching** - Switch developer profiles (GitHub + Cloudflare) with a single click
- **Keychain Integration** - Automatically updates credentials in macOS Keychain securely
- **Git Config Management** - Updates `git config --global user.name` and `user.email`
- **Cloudflare Integration** - Manages `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` in `~/.wrangler/config/default.toml` and launchctl environment.
- **Secure Storage** - Personal Access Tokens & API Tokens stored securely in Keychain (never in plain text)
- **Launch at Login** - Optionally start automatically when you log in
- **Native Notifications** - Get notified when account switches complete
- **No Dock Icon** - Runs as a background utility (menu bar only)
- **Dark Mode Support** - Follows your system appearance
- **Transparent Icons** - App icons with 100% transparent backgrounds for a professional look

## Requirements

- **macOS 13.0** (Ventura) or later
- **Xcode 15.0** or later (for building from source)
- **Git** installed (typically at `/usr/bin/git` or via Homebrew)
- **Wrangler / Cloudflare CLI** (optional, for Cloudflare deployments)

## Installation

### Option 1: Build from Command Line (Recommended)

```bash
# Clone the repository
git clone https://github.com/MinhOmega/GreatDeploy.git
cd GreatDeploy/GreatDeploy

# Clean any previous builds (recommended for fresh builds)
xcodebuild -project GreatDeploy.xcodeproj \
  -scheme GreatDeploy \
  clean

# Clear derived data cache (ensures clean build)
rm -rf ~/Library/Developer/Xcode/DerivedData/GreatDeploy-*

# Build the app (Release configuration)
xcodebuild -project GreatDeploy.xcodeproj \
  -scheme GreatDeploy \
  -configuration Release \
  build

# Find the built app
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/GreatDeploy-*/Build/Products/Release -name "GreatDeploy.app" -type d | head -1)

# Remove old version if exists
rm -rf /Applications/GreatDeploy.app

# Copy to Applications folder
cp -R "$APP_PATH" /Applications/

# Launch the app
open /Applications/GreatDeploy.app
```

**Quick One-Liner (Clean Build & Install):**
```bash
cd GreatDeploy/GreatDeploy && \
xcodebuild -project GreatDeploy.xcodeproj -scheme GreatDeploy clean && \
rm -rf ~/Library/Developer/Xcode/DerivedData/GreatDeploy-* && \
xcodebuild -project GreatDeploy.xcodeproj -scheme GreatDeploy -configuration Release build && \
rm -rf /Applications/GreatDeploy.app && \
cp -R ~/Library/Developer/Xcode/DerivedData/GreatDeploy-*/Build/Products/Release/GreatDeploy.app /Applications/ && \
open /Applications/GreatDeploy.app
```

### Option 2: Build with Xcode

```bash
# Clone the repository
git clone https://github.com/MinhOmega/GreatDeploy.git
cd GreatDeploy/GreatDeploy

# Open in Xcode
open GreatDeploy.xcodeproj
```

Then in Xcode:
1. Select your **Development Team** in Project Settings > Signing & Capabilities
2. Select **Product > Archive** for a release build, or press **Cmd+R** to build and run
3. For Archive: **Distribute App > Copy App** to export the `.app` file

### Option 3: One-Line Install Script

```bash
# Clone, build, and install in one command
git clone https://github.com/MinhOmega/GreatDeploy.git && \
cd GreatDeploy/GreatDeploy && \
xcodebuild -project GreatDeploy.xcodeproj \
  -scheme GreatDeploy \
  -configuration Release \
  -derivedDataPath build \
  build && \
cp -R build/Build/Products/Release/GreatDeploy.app /Applications/ && \
open /Applications/GreatDeploy.app
```

### Verify Installation

```bash
# Check if the app is installed
ls -la /Applications/GreatDeploy.app

# Check if it's running
pgrep -l GreatDeploy
```

### Uninstall

```bash
# Remove the app
rm -rf /Applications/GreatDeploy.app

# Remove app data (optional)
rm -rf ~/Library/Application\ Support/GreatDeploy
rm -rf ~/Library/Preferences/com.greatdeploy.plist

# Remove from Login Items (if enabled)
# System Settings > General > Login Items > Remove GreatDeploy
```

## Usage

### Adding an Account

1. Click the menu bar icon (shows current account or question mark if none)
2. Click **"Add Account"** or the **+** button
3. Fill in the details:
   - **Display Name**: A friendly name (e.g., "Personal", "Work", "Client-X")
   - **GitHub Username**: Your GitHub username
   - **Personal Access Token**: Your GitHub PAT ([create one here](#creating-a-personal-access-token))
   - **Git User Name**: The name for git commits (can differ from GitHub username)
   - **Git User Email**: The email for git commits
   - **Cloudflare Account ID**: (Optional) Your Cloudflare Account ID
   - **Cloudflare API Token**: (Optional) Your Cloudflare API Token
4. Click **"Add"**

### Switching Accounts

**From Menu Bar:**
1. Click the menu bar icon
2. Click on the account you want to switch to

**From Main Window:**
1. Click menu bar icon > **"Open Window"**
2. Click **"Switch"** button on any account card

When you switch accounts, the app will:
- Update GitHub credentials in macOS Keychain
- Run `git config --global user.name "Your Name"`
- Run `git config --global user.email "your@email.com"`
- Set up Cloudflare tokens in `~/.wrangler/config/default.toml` and via `launchctl`
- Show a notification (if enabled)

### Managing Accounts

- **Edit**: Click the **...** menu on any account card > **Edit**
- **Delete**: Click the **...** menu > **Delete**
- **Reorder**: Open Settings > Accounts tab (drag to reorder coming soon)

### Settings

Access Settings via:
- Menu bar > gear icon, or
- Main window > gear icon in footer, or
- **Cmd+,** when the app is focused

**General Settings:**
- Show notification on account switch
- Launch at login

### Creating a Personal Access Token

1. Go to [GitHub Settings > Developer settings > Personal access tokens](https://github.com/settings/tokens)
2. Click **"Generate new token (classic)"** or **"Fine-grained tokens"**

**For Classic Tokens:**
Select these scopes:
- `repo` - Full control of private repositories
- `read:user` - Read user profile data
- `user:email` - Access user email addresses

**For Fine-grained Tokens:**
- Repository access: All repositories (or select specific ones)
- Permissions: Contents (Read and write), Metadata (Read)

3. Click **"Generate token"** and **copy it immediately** (you won't see it again!)

## How It Works

### Keychain Management

The app manages GitHub credentials using the macOS Keychain Services API:

```
Keychain Entry:
├── Kind: Internet password
├── Server: github.com
├── Protocol: HTTPS
├── Account: <your-github-username>
└── Password: <your-personal-access-token>
```

This is the same entry that Git's credential helper (`osxkeychain`) uses when you run `git push` with HTTPS.

**App's Own Storage:**
Account metadata (display name, emails) is stored in the app's private Keychain entries, separate from the GitHub credential.

### Git Config Management

When switching accounts, the app executes:

```bash
git config --global user.name "Your Name"
git config --global user.email "your@email.com"
```

This updates `~/.gitconfig`:

```ini
[user]
    name = Your Name
    email = your@email.com
```

### Security Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Great Deploy                  │
├─────────────────────────────────────────────────────────┤
│  AccountStore (ObservableObject)                        │
│  - Coordinates all operations                           │
│  - Persists account metadata to UserDefaults            │
│  - DOES NOT store tokens in UserDefaults                │
├─────────────────────────────────────────────────────────┤
│  KeychainService (Singleton)                            │
│  - Stores/retrieves tokens from macOS Keychain          │
│  - Uses Security.framework APIs                         │
│  - Tokens encrypted at rest by macOS                    │
├─────────────────────────────────────────────────────────┤
│  GitConfigService (Singleton)                           │
│  - Executes git commands via Process API                │
│  - Manages global git configuration                     │
└─────────────────────────────────────────────────────────┘
```

## Project Structure

```
GreatDeploy/
├── GreatDeploy.xcodeproj/     # Xcode project file
├── GreatDeploy/
│   ├── GreatDeployApp.swift   # App entry point, MenuBarExtra, Windows
│   ├── Models/
│   │   └── GitAccount.swift          # Account data model (Codable)
│   ├── Services/
│   │   ├── KeychainService.swift     # macOS Keychain operations
│   │   ├── GitConfigService.swift    # Git command execution
│   │   └── AccountStore.swift        # State management (@MainActor)
│   ├── Views/
│   │   └── AddEditAccountView.swift  # Account form UI
│   ├── Assets.xcassets/              # App icons and colors
│   ├── Info.plist                    # Bundle configuration
│   └── GreatDeploy.entitlements
├── docs/                             # Documentation assets
├── build/                            # Build output (gitignored)
└── README.md                         # This file
```

## Troubleshooting

### "Keychain item not found"

**Cause:** No existing GitHub credential in Keychain.

**Solution:** This is normal for first-time use. The app will create the credential when you switch to an account.

### "Git command failed"

**Cause:** Git is not installed or not in expected location.

**Solution:**
```bash
# Check git installation
which git
# Expected: /usr/bin/git or /opt/homebrew/bin/git

# If not installed, install via Homebrew
brew install git

# Or install Xcode Command Line Tools
xcode-select --install
```

### Credentials not working after switch

**Cause:** Git credential helper not configured.

**Solution:**
```bash
# Check current credential helper
git config --global credential.helper
# Expected: osxkeychain

# If not set, configure it
git config --global credential.helper osxkeychain
```

### "The operation couldn't be completed" (Keychain error)

**Cause:** Keychain access denied or locked.

**Solution:**
1. Open **Keychain Access** app
2. Make sure your login keychain is unlocked
3. Try removing any existing `github.com` entries and let the app recreate them

### App doesn't appear in menu bar

**Cause:** App crashed or system UI issue.

**Solution:**
```bash
# Force quit and restart
pkill GreatDeploy
open /Applications/GreatDeploy.app

# Check Console.app for crash logs
open /Applications/Utilities/Console.app
```

### Build Errors

**"Signing requires a development team"**
- Open project in Xcode
- Select your team in Signing & Capabilities
- Or build with `CODE_SIGNING_ALLOWED=NO` for local testing:
  ```bash
  xcodebuild -project GreatDeploy.xcodeproj \
    -scheme GreatDeploy \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    build
  ```

**"No provisioning profile"**
- Sign in with Apple ID in Xcode > Settings > Accounts
- Select "Personal Team" for local development

## Security Considerations

### Why Not Sandboxed?

The app requires these capabilities that are incompatible with App Store sandboxing:

1. **Full Keychain Access** - Modify GitHub internet password entries
2. **Process Execution** - Run `git` commands via shell
3. **File System Access** - Read/write `~/.gitconfig`

### Token Security

- Tokens are stored in macOS Keychain (encrypted at rest)
- Tokens are never logged or stored in plain text
- Tokens are never stored in UserDefaults or plist files
- Each account's token is stored in a separate Keychain entry

### Best Practices

1. **Use fine-grained tokens** with minimal required permissions
2. **Set token expiration** dates (GitHub recommends 90 days or less)
3. **Rotate tokens regularly** - Update tokens in the app when you regenerate them
4. **Review Keychain Access** - Periodically check what apps have Keychain access

## Development

### Prerequisites

- macOS 13.0+
- Xcode 15.0+
- Swift 5.9+

### Building for Development

```bash
# Debug build
xcodebuild -project GreatDeploy.xcodeproj \
  -scheme GreatDeploy \
  -configuration Debug \
  build

# Run tests (when available)
xcodebuild -project GreatDeploy.xcodeproj \
  -scheme GreatDeploy \
  test
```

### Code Style

- SwiftUI with MVVM architecture
- `@MainActor` for UI-related code
- `async/await` for asynchronous operations
- `// MARK: -` comments for code organization
- Triple-slash (`///`) documentation for public APIs

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

## License

MIT License - Feel free to modify and distribute.

## Acknowledgments

- **Special Thanks**: GreatDeploy is a comprehensive upgrade and expansion of the original **GitAccountSwitcher** application. We sincerely thank the original authors (including MinhOmega) for providing the open-source foundation and excellent Keychain integration concepts that made this tool possible.
- Built with SwiftUI and the Security framework
- Uses native macOS Keychain Services API
- Icons from SF Symbols

---

<p align="center">
  Made with ❤️ for developers who deploy code across multiple accounts
</p>

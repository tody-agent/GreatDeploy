# Install Great Deploy Ad-Hoc Build

This package is signed with a free ad-hoc signature. It is intended for private sharing across your own Macs and is not notarized by Apple.

## Install

1. Unzip the package.
2. Copy `GreatDeploy.app` to `/Applications`.
3. Open it the first time with right-click, then choose **Open**.

## If macOS Blocks the App

If macOS says the app is from an unidentified developer, use right-click -> **Open** again, or go to **System Settings -> Privacy & Security** and choose **Open Anyway**.

If macOS says the app is damaged or cannot be opened, clear the quarantine attribute:

```bash
xattr -cr /Applications/GreatDeploy.app
open /Applications/GreatDeploy.app
```

Gatekeeper warnings are expected for this ad-hoc/private build path. A public release should use Developer ID signing and notarization instead.

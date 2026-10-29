<div align="center">

<img src=".github/icon.png" width="120" alt="AntCloud">

# AntCloud for iOS

**Cloud gaming on your iPhone — [AntCloud](https://antcloud.co) built right into Moonlight. One tap to connect, no manual pairing.**

![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.0-orange?logo=swift)
![Streaming](https://img.shields.io/badge/streaming-Moonlight-5A0FC8)
![Install](https://img.shields.io/badge/install-sideload-green)

</div>

---

A single iOS app that logs in to AntCloud, boots your cloud PC, and streams it — by building the
AntCloud control panel directly into the open-source
[Moonlight](https://github.com/moonlight-stream/moonlight-ios) client.

Tap **Play** and Moonlight takes over: it adds the cloud PC, pairs it automatically (the PIN is
submitted to AntCloud's backend for you), and launches Desktop. **No copying addresses, no typing PINs.**

## ✨ Features

- 🔐 **Login** with email/password or phone OTP — tokens in the iOS Keychain
- ☁️ **Start your cloud PC** right from the app
- ⚡ **One-tap Play** — auto-adds the host, auto-pairs, auto-launches Desktop
- 🔄 **Background keep-alive** so the session survives while you're in the stream
- 🔁 **Orientation-aware** — portrait control panel, landscape streaming
- ⏱️ **Expiry reminder** — free-Apple-ID builds last 7 days; the app tells you when and reminds you the day before
- 🛠️ **Developer toggle** for the client-side night-plan check

## 🚀 Build & install

**Requirements:** Xcode, an Apple ID for signing (free works), and
[`xcodeproj`](https://github.com/CocoaPods/Xcodeproj) + [libimobiledevice](https://libimobiledevice.org) for CLI installs.

```sh
# 1. Clone Moonlight next to this repo and fetch submodules
git clone https://github.com/moonlight-stream/moonlight-ios
git -C moonlight-ios submodule update --init --recursive

# 2. Integrate AntCloud (idempotent — applies patch, adds Swift + SocketIO, installs icon)
gem install --user-install xcodeproj
ruby integrate-moonlight.rb ./moonlight-ios

# 3. Build & sign for your device
cd moonlight-ios
xcodebuild -project Moonlight.xcodeproj -scheme Moonlight -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath build -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=<YOUR_TEAM_ID> PRODUCT_BUNDLE_IDENTIFIER=com.<you>.moonlight build
```

Then install the `.app` with `ideviceinstaller` or run it from Xcode.

> **Free Apple ID?** The app stops opening after 7 days. Rebuild and reinstall to renew — the app shows the exact expiry date.

## 📦 What's in this repo

| File | Purpose |
|---|---|
| `AntCloudPanel.swift`, `AntCloudHomeView.swift` | The SwiftUI control panel shown over Moonlight |
| `AppExpiry.swift` | Reads the signing profile's expiry and reminds you |
| `AntCloud-Bridging-Header.h` | Exposes Moonlight's settings to Swift |
| `Shared/` | API client, auth, session logic (shared with the Mac app) |
| `moonlight-objc.patch` | Edits to Moonlight's `MainFrameViewController.m`, `AppDelegate.m`, `Info.plist` |
| `integrate-moonlight.rb` | One command that wires it all into a Moonlight checkout |
| `AppIcon-1024.png` | App icon source |

## ⚠️ Note

Unofficial client, not affiliated with AntCloud. [Moonlight](https://github.com/moonlight-stream/moonlight-ios)
is GPLv3 — this repo ships only the AntCloud additions and a patch, never Moonlight's source.
`Shared/` is duplicated from [AntCloudMac](https://github.com/Sammy970/AntCloudMac); keep them in sync by hand.

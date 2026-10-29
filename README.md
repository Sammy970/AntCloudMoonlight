# AntCloud for iOS (Moonlight integration)

A single iOS app that logs in to [AntCloud](https://antcloud.co), starts your cloud PC, and
streams it — by building the AntCloud control panel directly into the open-source
[Moonlight](https://github.com/moonlight-stream/moonlight-ios) client.

Tapping **Play** in the panel hands off to Moonlight, which adds the cloud PC, pairs it
automatically (the PIN is submitted to AntCloud's backend for you), and launches Desktop.

## What's here

| File | Purpose |
|---|---|
| `AntCloudPanel.swift`, `AntCloudHomeView.swift` | The SwiftUI panel shown over Moonlight |
| `AppExpiry.swift` | Shows when a sideloaded (free Apple ID) build stops working |
| `AntCloud-Bridging-Header.h` | Exposes Moonlight's `DataManager`/`TemporarySettings` to Swift |
| `Shared/` | API client, auth, and session logic (shared with the Mac app) |
| `moonlight-objc.patch` | Edits to Moonlight's `MainFrameViewController.m`, `AppDelegate.m`, `Info.plist` |
| `integrate-moonlight.rb` | Applies the patch, adds the Swift files + SocketIO, installs the icon |
| `AppIcon-1024.png` | App icon source |

## Build

```sh
# 1. Clone Moonlight next to this repo and fetch its submodules
git clone https://github.com/moonlight-stream/moonlight-ios
git -C moonlight-ios submodule update --init --recursive

# 2. Integrate (idempotent)
gem install --user-install xcodeproj
ruby integrate-moonlight.rb ./moonlight-ios

# 3. Build & sign for your device (free Apple ID works; app expires after 7 days)
cd moonlight-ios
xcodebuild -project Moonlight.xcodeproj -scheme Moonlight -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath build -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=<YOUR_TEAM_ID> PRODUCT_BUNDLE_IDENTIFIER=com.<you>.moonlight build
```

Install the resulting `.app` with `ideviceinstaller` (libimobiledevice) or run from Xcode.

## Notes

- `Shared/` is duplicated from the Mac app's `Sources/Shared`. Keep them in sync by hand.
- Moonlight is GPLv3; this repo holds only the AntCloud additions and a patch, not Moonlight's source.

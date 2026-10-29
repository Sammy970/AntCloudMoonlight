<div align="center">

<img src=".github/icon.png" width="112" alt="AntCloud icon">

# AntCloud for iPhone

**Your AntCloud gaming PC on your iPhone. Start it, tap Play, and you're in.**<br>
AntCloud built into the open-source Moonlight client: one app, automatic pairing, no addresses or PINs to type.

<p>
  <img src="https://img.shields.io/badge/iOS-17%2B%20·%20glass%20on%2026%2B-111111?style=flat-square&logo=apple&logoColor=white" alt="iOS 26+">
  <img src="https://img.shields.io/badge/Swift-5-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/UI-Liquid%20Glass-4A86E8?style=flat-square" alt="Liquid Glass">
  <img src="https://img.shields.io/badge/streams%20with-Moonlight-5A0FC8?style=flat-square" alt="Streams with Moonlight">
  <img src="https://img.shields.io/badge/unofficial-not%20affiliated%20with%20AntCloud-B42318?style=flat-square" alt="Unofficial">
</p>

<p><a href="#what-it-does">What it does</a> &nbsp;·&nbsp; <a href="#build-and-install">Build and install</a> &nbsp;·&nbsp; <a href="#renewing-every-7-days">Renewing every 7 days</a> &nbsp;·&nbsp; <a href="#how-it-works">How it works</a></p>

</div>

> [!IMPORTANT]
> **Unofficial project.** This is an independent client built by a user. It is not made, endorsed or supported by AntCloud.
> "AntCloud" and the AntCloud logo belong to their owners. Use it with your own AntCloud account, and follow AntCloud's terms of service.

## What it does

The app is called **AntCloud** on your home screen and opens straight into it, in portrait. Moonlight only
does the streaming underneath; you never see its host list or settings.

- **Sign in** with email and password or a phone code. Tokens are kept in the iOS Keychain.
- **Your plan up top:** time left this month, the renewal date and a readable plan name, like "Premium Night".
- **Start Cloud PC, then Play.** A drawn monitor and a Connect → Boot → Ready → Stream track show where the session is.
  Play adds the cloud PC to Moonlight, pairs it (the PIN goes to AntCloud's backend for you) and launches Desktop in landscape.
- **Back to AntCloud** as soon as the stream ends.
- **Stream settings in the app:** resolution up to 4K, 30/60/120 FPS, bitrate with data use per hour, HEVC,
  trackpad or direct touch, on-screen controls, stats overlay and where the sound plays. They're saved straight into Moonlight.
- **Network check** before you start: latency to AntCloud's servers, jitter, packet loss and download speed,
  with a verdict and a one-tap bitrate suggestion.
- **Night plans checked up front:** outside 12:30–9:30 AM IST the app says so before it boots anything.
- **In-stream overlay:** a small pill at the top of the stream shows time left and latency; tap it for the
  full card. It warns you when the cloud PC's connection gets busy and when plan time runs low.
- **Liquid Glass on iOS 26+,** with a soft aurora behind it, purposeful motion and haptics. Reduce Motion is respected.
  iOS 17–25 get a frosted-material version of the same design.
- **Expiry reminder:** free Apple ID builds last 7 days; the app shows the exact date and reminds you the day before.

## Build and install

You need Xcode, an Apple ID for signing (a free one works), and the
[`xcodeproj`](https://github.com/CocoaPods/Xcodeproj) gem.

```sh
# 1. Clone Moonlight next to this repo and fetch its submodules
git clone https://github.com/moonlight-stream/moonlight-ios
git -C moonlight-ios submodule update --init --recursive

# 2. Add AntCloud to it (safe to re-run: applies the patch, adds the Swift files,
#    SocketIO, the icon, the launch screen and the "AntCloud" name)
gem install --user-install xcodeproj
ruby integrate-moonlight.rb ./moonlight-ios

# 3. Point the install script at your signing details, then build and install
cp scripts/renew.env.example scripts/renew.env   # set TEAM_ID and BUNDLE_ID
scripts/renew-and-install.sh
```

The script finds your iPhone over Wi-Fi or USB, builds, installs and prints when the app expires.
Moonlight is built in the Debug configuration on purpose: the Release build only accepts local network
addresses, and a cloud PC isn't on your network.

## Renewing every 7 days

Apps signed with a free Apple ID stop opening 7 days after their signing profile was made, and a plain
rebuild reuses the old profile, so the date doesn't move. To restart the 7 days:

```sh
scripts/renew-and-install.sh              # new profile, rebuild, install
scripts/renew-and-install.sh --integrate  # same, after pulling changes to this repo
scripts/renew-and-install.sh --skip-renew # rebuild and install, keep the current expiry
```

Keep the iPhone unlocked and on the same Wi-Fi as the Mac. Your sign-in and settings survive a reinstall.
A paid Apple Developer account makes builds last a year instead.

## How it works

```
AntCloud panel ── Start ──▶ Socket.IO session queues and boots the cloud PC
      │
     Play ──▶ cloud PC address ──▶ Moonlight adds the host
                                        │
                     pairing PIN ──▶ AntCloud backend (automatic)
                                        │
                                  Desktop launches ──▶ stream ends ──▶ back to the panel
```

## What's in this repo

| Path | What's there |
|---|---|
| `AntCloudPanel.swift` | Entry points Moonlight calls, the app-wide session store, orientation, launch splash |
| `AntCloudHomeView.swift` | The home screen |
| `StreamSettingsSheet.swift` | In-app stream settings, saved into Moonlight's settings database |
| `AppExpiry.swift` | Reads the signing profile's expiry and schedules the reminder |
| `Shared/` | API client, sign-in, session logic and shared views (same code as the Mac app) |
| `moonlight-objc.patch` | Moonlight changes: launch into AntCloud, auto-connect and pair, return after the stream, orientation, launch screen, name |
| `integrate-moonlight.rb` | Wires everything into a Moonlight checkout |
| `scripts/renew-and-install.sh` | Renews the signing profile, builds and installs |
| `Assets/`, `AntCloudLogo.png`, `AppIcon-1024.png` | Launch screen colour and logo, sign-in logo, app icon |

## Notes

Unofficial client, not affiliated with AntCloud. [Moonlight](https://github.com/moonlight-stream/moonlight-ios)
is GPLv3; this repo ships only the AntCloud additions and a patch, never Moonlight's source.
`Shared/` is copied from [AntCloudMac](https://github.com/Sammy970/AntCloudMac); keep the two in sync.

# TV Remote — native iOS app (no server)

A serverless, native SwiftUI rewrite of the Samsung TV web remote. Everything the
Go server did now runs **on the iPhone itself** — no always-on server, no Docker,
nothing on your network except the app and the TV.

## What it does

| Go server (`server/main.go`)         | iOS replacement                                   |
| ------------------------------------ | ------------------------------------------------- |
| `wss://TV:8002` + self-signed cert   | `URLSessionWebSocketTask` + TLS trust override    |
| Wake-on-LAN UDP broadcast            | `WakeOnLAN.swift` (BSD socket, `SO_BROADCAST`)    |
| Pairing token (`TOKEN_FILE`)         | Keychain (`TokenStore.swift`)                     |
| Power state via `http://TV:8001`     | `SamsungTVClient.powerState` / `activeApp`        |
| App-icon favicon proxy               | `AppIconView` fetches favicons directly           |
| Apps list / launch / key send / hold | `SamsungTVClient`                                  |
| Web UI (`client/index.html`)         | SwiftUI (`RemoteView` + drawer + settings)        |
| `TV_IP` config                       | **Auto-discovery via Bonjour/mDNS** + manual IP   |

Feature parity with the web client: power (Wake-on-LAN to turn on), now-playing,
numpad, D-pad with press-and-hold repeat, volume/mute, Back/Home/Menu, media
transport, apps grid, and long-press favorites.

## Requirements

- A **Mac with Xcode** (Xcode only runs on macOS).
- An iPhone on the **same Wi-Fi** as the TV.
- A Samsung Smart TV (Tizen, the `samsung.remote.control` WS API).

### Apple account / cost

- **Free Apple ID — 0 Kč:** install on your own iPhone. The app's signature
  expires after **7 days**; re-run from Xcode to refresh it.
- **Apple Developer Program — 99 USD/year (~2 500 Kč):** only needed for
  TestFlight, the App Store, or to avoid the 7-day re-sign. Not required for
  personal use.

## Build & run

The Xcode project isn't checked in; generate it from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (keeps the repo diff-friendly):

```sh
brew install xcodegen
cd ios
xcodegen generate
open TVRemote.xcodeproj
```

Then in Xcode:

1. Select the **TVRemote** target → **Signing & Capabilities** → pick your Team
   (your free Apple ID is fine).
2. Plug in your iPhone, select it as the run destination, press **⌘R**.
3. On first launch, **allow Local Network access** when prompted — this is
   required for both discovery and talking to the TV.

### No XcodeGen? Create the project manually

1. Xcode → New → App → SwiftUI, name `TVRemote`.
2. Delete the auto-generated `ContentView.swift` / `*App.swift`.
3. Drag the contents of `ios/Sources/` into the target.
4. Set the target's Info.plist to `Sources/Info.plist` (or copy these keys into
   the generated one): `NSLocalNetworkUsageDescription`, `NSBonjourServices`
   (`_samsungmsf._tcp`), and `NSAppTransportSecurity → NSAllowsLocalNetworking`.

## First use

1. Open the app → **Settings** opens automatically.
2. Your TV appears under **Discovered TVs** (turn the TV on so it advertises).
   Tap it. Or type its IP under **Manual IP**.
3. The TV shows a pairing prompt the first time — **Allow**. The token is saved
   to the Keychain.
4. (Optional) Enter the TV's **MAC address** to enable powering the TV **on** via
   Wake-on-LAN. Without it, the power button can only turn the TV off.

## Project layout

```
ios/
├── project.yml                 # XcodeGen spec
└── Sources/
    ├── App/TVRemoteApp.swift   # @main entry
    ├── Info.plist
    ├── Theme.swift             # colours + haptics
    ├── Models/                 # TVApp, RemoteKey, AppDomains
    ├── Services/
    │   ├── SamsungTVClient.swift   # WebSocket control + REST queries
    │   ├── WakeOnLAN.swift
    │   ├── TVDiscovery.swift       # Bonjour/mDNS
    │   └── TokenStore.swift        # Keychain
    ├── ViewModels/RemoteViewModel.swift
    └── Views/                  # RemoteView, AppsDrawerView, SettingsView, …
```

The original Go server and PWA under the repo root are untouched — this is an
alternative, server-free client.

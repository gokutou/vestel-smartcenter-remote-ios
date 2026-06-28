# Vestel Remote

> A SwiftUI iOS app to control Vestel / Toshiba (and other Vestel-platform) smart TVs over your local network — built without a Mac and run without code signing.

![Platform](https://img.shields.io/badge/platform-iOS-blue)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-orange)
![Mac](https://img.shields.io/badge/built%20without-a%20Mac-success)
![License](https://img.shields.io/badge/license-MIT-green)

Vestel manufactures TVs sold under many brands (Toshiba, Hitachi, Telefunken, JVC, Finlux, Regal, and others). Most of them expose a simple, undocumented HTTP remote-control API on the local network — the same one the official *Smart Center* app uses. This app talks to that API directly: it discovers the TV on your Wi‑Fi and sends remote keys, on‑screen-keyboard text, app shortcuts, and **trackpad-style cursor control**.

The whole thing is a single Swift file and was developed entirely on Linux (no Mac, no paid Apple Developer account).

---

## Features

- **Auto-discovery** of the TV on your local subnet, with a manual-IP fallback and a clear retry state.
- **Full remote keypad** — power, source, mute, D‑pad + OK, volume, back/home, media transport, color buttons, info / subtitle / EPG / favorites / menu / aspect / teletext / language.
- **Press-and-hold auto-repeat** on the D‑pad arrows.
- **On-screen keyboard** for typing into the TV's built-in browser.
- **App shortcuts** — Netflix, YouTube, Prime Video, Browser, Rakuten, Settings.
- **Touchpad / air-mouse mode** — drag to move the cursor, tap to click. Uses the same `mouseevent` command the official app sends (verified via packet capture).
- **Persistent sensitivity slider** — set the cursor speed once; it's saved on the device.
- Adaptive layout that fits any screen; controls stay disabled until a TV is connected.

---

## Screenshots
<p align="center">
  <img src="https://github.com/user-attachments/assets/70c509e1-1d90-454d-bde9-20d12e814a93" width="240" alt="Remote">
  <img src="https://github.com/user-attachments/assets/ef1e6073-ec09-48ba-8fb3-db368bb1a720" width="240" alt="Remote (scrolled)">
  <img src="https://github.com/user-attachments/assets/6717d9f4-12c0-4a8d-96b3-372741e066be" width="240" alt="Touchpad">
</p>

---

## How it works

Phone and TV must be on the same Wi‑Fi network. The app finds the TV's IP, then sends small XML commands over HTTP:

```
iPhone  ──HTTP POST (XML)──▶  http://<TV_IP>:56789/apps/SmartCenter  ──▶  TV
```

Each command is a short XML body the TV processes exactly as if it came from the official app or the physical remote.

**Prerequisite (on the TV):** *Virtual Remote* must be enabled in the TV's settings. (If remote keys and keyboard input work, it's already on.)

---

## TV Protocol Reference

This is the reverse-engineered API, in case it's useful for other projects (Home Assistant, scripts, other platforms…). Everything is a `POST` to `http://<TV_IP>:56789/apps/SmartCenter`.

### Request format

```
POST /apps/SmartCenter HTTP/1.1
application_name: vestel smart center
Content-Type: text/plain; charset=ISO-8859-1

<XML body>
```

- The `application_name: vestel smart center` header is required.
- The body must be encoded as **ISO‑8859‑1 (Latin‑1)**.
- A successful command returns `HTTP/1.1 201 Created`.

### Commands

**Remote key**

```xml
<?xml version='1.0' ?><remote><key code='XXXX'/></remote>
```

**Keyboard character** (works in the TV's built-in browser only — see Limitations)

```xml
<?xml version='1.0' ?><keyboard><key value='UNICODE'/></keyboard>
```
`UNICODE` is the character's Unicode code point (e.g. `a` → `97`).

**Open a portal app**

```xml
<?xml version='1.0' ?><browserseturl><load url='http://www.portaltv.tv/swf/APPNAME/APPNAME.swf' page='RC'/></browserseturl>
```
e.g. `APPNAME=amazon` for Prime Video.

**Mouse move** (relative deltas; `button='0'` = move only)

```xml
<?xml version='1.0' ?><mouseevent><event_data dx='5' dy='-22' button='0'/></mouseevent>
```

**Mouse click** (press then release — verified via packet capture)

```xml
<?xml version='1.0' ?><mouseevent><event_data dx='0' dy='0' button='1'/></mouseevent>
<?xml version='1.0' ?><mouseevent><event_data dx='0' dy='0' button='0'/></mouseevent>
```

The official app opens a separate HTTP request (and TCP connection) per mouse event; this app does the same.

### Key codes

| Code | Function | Code | Function | Code | Function |
|------|----------|------|----------|------|----------|
| 1000–1009 | Digits 0–9 | 1024 | Stop | 1052 | Blue |
| 1010 | Back | 1025 | Play | 1053 | OK |
| 1011 | Aspect | 1027 | Rewind | 1054 | Green |
| 1012 | Power | 1028 | Fast-forward | 1055 | Red |
| 1013 | Mute | 1031 | Subtitle | 1056 | Source |
| 1015 | Language | 1037 | Close | 1057 | Mirror |
| 1016 | Volume + | 1040 | Favorites | 1058 | Teletext |
| 1017 | Volume − | 1047 | EPG | 1062 | YouTube |
| 1018 | Info | 1048 | Menu / Home | 1063 | Main screen |
| 1019 | Down | 1049 | Pause | 1064 | Netflix |
| 1020 | Up | 1050 | Yellow | 1065 | Browser |
| 1021 | Left | 1051 | Record | 1066 | Settings |
| 1022 | Right | | | 1067 | Ambilight |
| 1070 / 1071 / 1072 | Virtual remote variants | | | 1068 | Multi view |
| | | | | 1073 | Rakuten TV |

---

## Requirements

- An iOS device with **[LiveContainer](https://github.com/LiveContainer/LiveContainer)** installed.
- A Vestel-platform smart TV with **Virtual Remote** enabled, on the **same Wi‑Fi network** as the phone.

---

## Install

Download the latest `VestelRemote.ipa` from the [**Releases**](../../releases) page, then:

1. Open **LiveContainer**, tap **+** (top-right), and import the `.ipa`.
2. Launch it once, then turn on **Settings → LiveContainer → Local Network**.
3. Make sure **Virtual Remote** is enabled on the TV and the phone is on the same Wi-Fi.

To verify your download, compare its checksum against the SHA-256 published in the release notes:

```bash
sha256sum VestelRemote.ipa
```

---

## Build from source

This app is built with **[xtool](https://github.com/xtool-org/xtool)** — a cross‑platform Swift/iOS toolchain that runs on Linux, so **no Mac is required** — and installed with **LiveContainer**, which runs unsigned apps, so **no paid Apple Developer account or code signing is needed**.

In short: build an `.ipa` with xtool, then import it into LiveContainer on the phone and grant it Local Network access. The entire app is the single file [`VestelRemote.swift`](VestelRemote.swift), so it's easy to read and modify.

> Detailed build, SDK-extraction and signing notes are intentionally kept out of this README. See the project notes if you need the full toolchain walkthrough.

---

## Configuration

A few tunable parameters in the source:

| What | Where | Default |
|------|-------|---------|
| Cursor sensitivity | Touchpad slider (persisted) | 1.3× (range 0.4–4.0) |
| Mouse send rate | `TrackpadView` → `sendInterval` | 0.033 s (~30 Hz) |
| D‑pad first-repeat delay | `HoldButton` → first `Task.sleep` | 0.4 s |
| D‑pad repeat interval | `HoldButton` → second `Task.sleep` | 0.12 s |
| Discovery concurrency | `discover` → `maxInFlight` | 40 |
| Per-host scan timeout | `portOpen` call | 0.8 s |

---

## Limitations

- **Discovery is a unicast subnet scan** of your `/24` (port 56789). It won't find a TV on a different subnet/VLAN and can be a little slow. SSDP/mDNS would be cleaner but require the multicast entitlement, which isn't available when running this way — hence the scan.
- **One-way (fire-and-forget) commands.** The app doesn't read state back from the TV, so it can't show power/volume/source/channel, and it fails silently if the TV is off or the IP is wrong.
- **Cursor latency.** Each mouse move is a separate HTTP request, so the pointer is inherently a bit laggy (the official app has the same characteristic).
- **Keyboard input doesn't work in YouTube.** Apps like YouTube run as a separate sandboxed runtime that only receives remote *key codes*, not keyboard/IME injection — a TV-side architectural limit, not something the app can fix. Text entry works in the TV's built-in browser.
- **Not an App Store app.** It depends on LiveContainer and the Local Network permission staying enabled. Fine for personal use; iOS updates can occasionally break this style of sideloading.

---

## Roadmap

- [ ] Remember the last TV IP and skip the scan on launch
- [ ] Press-and-hold auto-repeat on the volume keys
- [ ] Numeric keypad (key codes 1000–1009)
- [ ] Right-click / long-press and two-finger scroll on the touchpad
- [ ] A connection/health indicator
- [ ] **Two-way:** read TV state (power, source, volume, channel) by reverse-engineering the app's status/EPG queries
- [ ] Investigate the TV's WebSocket channel for lower-latency mouse / telemetry
- [ ] Discovery improvements: pick from multiple TVs, faster scan, caching

---

## Disclaimer

This is an independent, unofficial project for personal use and interoperability. It is **not affiliated with, endorsed by, or supported by** Vestel, Toshiba, or any related company. The protocol described here was observed on a local network for the purpose of interoperating with hardware the author owns. *Vestel*, *Toshiba*, and other names are trademarks of their respective owners. Provided **as is**, without warranty of any kind — use at your own risk.

---

## License

MIT License. See [`LICENSE`](LICENSE).

---

## Acknowledgements

- [xtool](https://github.com/xtool-org/xtool) — building iOS apps from Linux.
- [LiveContainer](https://github.com/LiveContainer/LiveContainer) — running apps without code signing.
- [Claude](https://claude.ai) (Anthropic) — helped reverse-engineer the protocol and build the app.

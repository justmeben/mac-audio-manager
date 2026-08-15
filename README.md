# AudioManager

**A tiny native macOS utility for two things the system stubbornly hides: rescuing Bluetooth headphones from "telephone-quality" mode, and mixing volume & output devices per app.**

No kernel extensions. No virtual audio drivers. No background daemons. Just SwiftUI and the modern Core Audio process-tap API.

![Platform](https://img.shields.io/badge/platform-macOS%2014.4%2B-blue)
![Swift](https://img.shields.io/badge/swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Why

**The Bluetooth problem.** Bluetooth headphones can't do high-quality stereo (A2DP) and microphone capture (HFP/SCO) at the same time. The moment macOS decides to use your headset's mic — often just because it auto-selected it as the input device — the *entire* link drops to 16 kHz mono. Music suddenly sounds like a phone call from 1998, and nothing in the Sound settings tells you why. AudioManager shows you exactly which profile each Bluetooth device is in, and switches modes with one click.

**The mixer problem.** macOS has one output device and one volume for everything. There's no built-in way to make your browser quieter than your game, or send a music player to the speakers while everything else stays on the headphones. AudioManager gives every app its own volume slider and output-device picker — in essence, the per-app volume mixer Windows has had built in for years, brought to macOS.

## Features

### 🎧 Devices
- All input/output devices with transport type and **live sample rate**
- One-click default input/output switching, master volume slider
- **Bluetooth quality badge** — instantly see whether a headset is in
  full-quality A2DP (green) or degraded call mode / HFP (orange)
- **Mode switch** per Bluetooth headset:
  - **High quality (music)** — frees the headset mic so the link renegotiates
    to A2DP stereo
  - **Headset mic (calls)** — uses the headset's microphone, accepting the
    call-quality drop that Bluetooth requires

### 🎚️ App Mixer
- Lists every app that plays audio (currently-playing apps first)
- Flip **Control** on for any app to get:
  - A per-app volume slider (0–150 %)
  - A per-app output device — game on the headset, browser on the speakers,
    music on the AirPlay set, all at once
- Apps routed to "Default device" follow the system default automatically

## Install

Build from source (requires Xcode command-line tools, macOS 14.4+):

```bash
git clone https://github.com/justmeben/AudioManager.git
cd AudioManager
./build.sh
open dist/AudioManager.app
```

Optionally move `dist/AudioManager.app` to `/Applications`.

## How it works

Per-app control uses the **Core Audio process tap** API introduced in macOS
14.4 (`CATapDescription` / `AudioHardwareCreateProcessTap`) — the same
mechanism modern commercial tools use, with no drivers to install:

1. When you enable **Control** for an app, AudioManager creates a process tap
   with `mutedWhenTapped`, which removes the app's audio from its normal
   output path.
2. The tap is attached to a private aggregate device whose output is whichever
   device you picked.
3. A realtime IO proc re-renders the tapped stream to that device, scaling it
   by your chosen gain (vDSP, so effectively free).

The Bluetooth mode switch works with the OS rather than against it: macOS
drops a Bluetooth link to HFP whenever the headset's own microphone is the
system input. "High quality" simply moves the default input to the built-in
mic, and the link renegotiates back to A2DP within a couple of seconds.

## Permissions

The first time you enable **Control** for an app, macOS asks for **System
Audio Recording** permission (System Settings → Privacy & Security → Screen &
System Audio Recording). This is what the tap API requires. AudioManager
never records, stores, or transmits audio — samples go straight back out to
the output device you chose.

## Limitations

- macOS **14.4 or newer** (the process-tap API doesn't exist earlier).
- Quit with ⌘Q. Taps are destroyed on exit; if AudioManager is force-killed,
  a controlled app may stay silent until it restarts its audio stream (or you
  toggle Control off/on again).
- Device state is polled every 2 s, so profile flips show up with a short
  delay.
- Devices without a virtual main volume (some HDMI/DisplayPort sinks) don't
  show the master volume slider.
- Unsigned local build — Gatekeeper may require right-click → Open on first
  launch if you move the app to another machine.

## Development

Plain Swift Package Manager — `swift build`, or open the folder in Xcode.
`build.sh` wraps the release build and produces a signed (ad-hoc) `.app`
bundle in `dist/`.

```
Sources/AudioManager/
├── App.swift                 # SwiftUI app + lifecycle (tap cleanup on quit)
├── ContentView.swift         # Tab container
├── DevicesView.swift         # Devices tab UI
├── MixerView.swift           # App Mixer tab UI
├── AudioDeviceManager.swift  # Device enumeration, defaults, volume, BT modes
├── AppMixerController.swift  # Audio-process discovery + managed-app state
├── ProcessTapPlayer.swift    # Tap + aggregate device + realtime IO proc
└── CoreAudioSupport.swift    # Thin helpers over the C property API
```

Contributions welcome — issues and PRs alike.

## License

[MIT](LICENSE)

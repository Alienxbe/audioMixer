# Audio Mixer — DankMaterialShell plugin

A pavucontrol-style audio mixer for the [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) bar.

## Features

**Bar widget**
- Output volume icon + percentage, microphone state icon (red when muted)
- Scroll to change volume, middle-click to mute output, right-click to mute the microphone
- Left-click opens the mixer

**Mixer popout** (same tabs as pavucontrol)
| Tab | What it controls |
|---|---|
| Playback | Per-application volume / mute, and which output device each app plays on |
| Recording | Per-application microphone volume / mute, and which input each app records from |
| Output | Output devices: volume, mute, set default, port (e.g. Speakers / Headphones) |
| Input | Input devices: volume, mute, set default, port (e.g. Internal Microphone / Headset Microphone) |
| Config | Card profiles (e.g. Analog Stereo Duplex, HDMI) |

- Live level meters for every device and stream (PipeWire peak monitor)
- Application names and icons resolved from installed desktop entries
- Rows update in place, so sliders and dropdowns are never reset while you use them

**Headset jack handling**
- When a headset is plugged into the combo jack, the headset microphone is selected automatically, and the shell falls back to the internal mic on unplug
- Optional notification on plug / unplug

## Requirements

- DankMaterialShell with plugin support (tested with DMS 2.1.2, Quickshell 0.3.2)
- PipeWire with `pipewire-pulse`
- `pactl` (package `pulseaudio-utils`)

## Installation

```sh
git clone <this-repo-url> ~/.config/dms/plugins/audioMixer
```

Then, in DMS:
1. **Settings → Plugins** → enable **Audio Mixer**
2. **Settings → Bar widgets** → add **Audio Mixer** to your bar

## Settings

Available under **Settings → Plugins → Audio Mixer**:

- Show volume percentage / microphone icon on the bar
- Scroll step (1, 2, 5, 10 %)
- Maximum slider volume (100 % or 150 %)
- Show level meters
- Show monitor sources ("Monitor of …" inputs)
- Switch microphone automatically on plug / unplug
- Notify on plug / unplug

## How it works

Device and stream state comes from `pactl -f json` and is refreshed on every `pactl subscribe` event. All changes are applied via `pactl`, and level meters use Quickshell's `PwNodePeakMonitor`.

## Troubleshooting

- **Settings page says "Failed to load settings" after editing the plugin:** run `dms restart`. Reloading a plugin repeatedly can stop DMS from loading its settings page until the shell restarts.
- **Microphone meter always at maximum:** lower the input volume. On many laptops, input volume above about 40 % also raises the hardware mic boost.

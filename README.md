# MixBar

A menu bar app for macOS that controls RME TotalMix FX over Global OSC.
Built for a Fireface UCX II, and works with any interface TotalMix FX 2.1+
supports.

- **Outputs:** volume slider, mute, and Comp/EQ for each chosen output (Main
  and Phones by default), with your own labels.
- **Volume keys:** the Mac's volume up/down/mute keys (and mice or keyboards
  that send them) control a TotalMix output instead of macOS. Step 1–10 dB,
  ⇧⌥ for quarter steps, a "never louder than" ceiling, and an on-screen
  overlay. By default this only happens while the RME is the Mac's sound
  output; otherwise the keys work as normal.
- **Mute key:** Dim (or mute the output). **⇧⌘M:** Mono.
- **Control Room:** Speaker B, Dim, Mono.
- **Inputs:** 48V, Instrument, Comp and EQ for chosen inputs (by default the
  ones with preamp switches).
- **Gain knobs (optional):** turn on in Settings for a gain knob on each input;
  drag up/down, ⌥ for fine steps. Ranges per interface are in `GainRanges.swift`.
- **Stereo pairs:** link or unlink input pairs (1+2, 3+4 …) in Settings or by
  right-clicking an input. TotalMix copies the left input's settings onto the
  right when linking.
- **48V lock:** untick an input in Settings and MixBar will never switch its
  48V on (it can still switch it off).
- **Levels window:** an always-on-top input meter strip with peak hold; a
  channel name turns red on clipping until you click it.
- Updates itself from this repo, and every error has a code (see
  [ERRORS.md](ERRORS.md)).

MixBar talks only to TotalMix on your own Mac (UDP on 127.0.0.1) and, for
update checks, to `raw.githubusercontent.com`.

## TotalMix setup

TotalMix FX 2.1 or newer, **Options → Settings → OSC**:

1. Pick a Remote Controller slot and tick **In Use**.
2. **Port incoming** 7001, **Port outgoing** 9001, **IP or Host Name** 127.0.0.1.
3. **Compatibility (Mode): Global OSC.** Under Details, tick **Send changes**
   and **Send status**.
4. Tick **Send Level Data** for the Levels window.
5. **Options → Enable OSC Control** must be ticked.

MixBar's Settings has the same steps and lets you change host and ports.

## Build and install

Command Line Tools only, no Xcode.

```bash
./install.sh
```

builds the app, copies it to `~/Applications` (apps can't run from Dropbox),
re-signs it ad-hoc, resets the Accessibility grant (every rebuild voids it),
and launches it. Grant Accessibility when asked.

- `./build.sh` — local build only (`MixBar.app` in this folder).
- `./test.sh` — protocol tests against a fake TotalMix
  (`Tests/fake_totalmix.py`). `./test.sh --snapshot <dir>` renders the popover
  to PNGs.
- `UPDATE_NOTES="…" ./release.sh` — universal build, writes `updates/MixBar.zip`
  and `updates/latest.json`; commit and push `updates/` to ship.

## How it works

| File | What it does |
|---|---|
| `OSC.swift` | OSC encode/decode and one UDP socket (send to TotalMix, listen for replies) |
| `Mixer.swift` | Live mirror of TotalMix's state; parses Global OSC, sends commands; fader curve |
| `Prefs.swift` | Settings and which channels the menu shows |
| `MediaKeys.swift` | Event tap for the volume keys; CoreAudio check for the RME being the sound output |
| `ContentView.swift` | The popover |
| `GainRanges.swift` | Input gain range and step per RME interface |
| `LevelsWindow.swift`, `HUD.swift`, `SettingsView.swift` | Levels window, volume overlay, settings |
| `Updater.swift`, `Errors.swift` | Self-updater and coded errors (same pattern as PasteStack) |

Global OSC addresses used: `/output/N/volume` (dB), `/output/N/mute`,
`/{input,output}/N/{name,color,stereo,dynamics/enable,eq/enable}`,
`/input/N/{48v,instrument,gain}`, `/controlroom/{dim,mainmono,speakerb}`,
`/level/in/N`, `/status/device`, and `/sendall` / `/sendstate` to request state.
Channel indexes are zero-based; a stereo pair is addressed by its left channel.

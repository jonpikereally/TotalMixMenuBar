# MixBar error codes

Every error MixBar shows has a code like `MB-204`. Find your code below to see
what happened and what to try.

**Getting help from an AI assistant:** click **Copy Details** (in the popover)
or **Copy Error Details** (in an alert), then paste it into your assistant
together with a link to this page (or its plain-text version:
https://raw.githubusercontent.com/jonpikereally/TotalMixMenuBar/main/ERRORS.md). The
details include the code, what went wrong, and your MixBar and macOS versions.

Where errors show up:

- **The popover banner** at the top of MixBar's menu shows connection and
  permission problems with their code and a **Copy Details** button.
- **Alerts** show the code, plus **Copy Error Details** and **Open Error List**
  buttons. Hovering over the error text points you here.
- **Background problems** appear as a **⚠️ Problem MB-xxx** row in the menu.
- **The installers** (install.sh, Install MixBar.command) print their code in
  the Terminal window.
- Every error is also logged to `~/Library/Application Support/MixBar/errors.log`.

## Updates (1xx)

| Code | What happened | What to try |
|---|---|---|
| MB-101 | No update source is set. | Set one with **Update Source…** in the menu, or leave it empty to use the built-in source. |
| MB-102 | The update source isn't a web link or a file path. | Fix it with **Update Source…**, or empty it to use the built-in source. |
| MB-103 | Couldn't reach the update source. | Check your internet connection and try again. |
| MB-104 | The update server returned an error. | Try again in a few minutes. If it keeps happening, download the latest version from GitHub. |
| MB-105 | The update information is damaged or in the wrong format. | The published update is broken. Download the latest version from GitHub instead. |
| MB-106 | Couldn't download the update. | Try again in a few minutes, or download the latest version from GitHub. |
| MB-107 | Couldn't unpack the downloaded update. | Download the latest version from GitHub instead. |
| MB-108 | The downloaded update doesn't contain MixBar. | Download the latest version from GitHub instead. |
| MB-109 | The downloaded update is a different app. | Download the latest version from GitHub instead. |
| MB-110 | The downloaded update is damaged. | Download the latest version from GitHub instead. |
| MB-111 | Couldn't start installing the update. | Make sure MixBar is in ~/Applications and that the folder isn't locked, then try again. |
| MB-112 | Installing the update failed, so the previous version was kept. | Make sure MixBar is in ~/Applications and that the folder isn't locked, then try again. |

## Talking to TotalMix (2xx)

| Code | What happened | What to try |
|---|---|---|
| MB-201 | Couldn't open a network socket to talk to TotalMix. | Quit and reopen MixBar. If it keeps happening, restart the Mac. |
| MB-202 | MixBar's OSC listening port is already in use by another app. | Another OSC app (a Stream Deck plugin, Companion, TouchOSC…) listens on the same port. Give MixBar its own TotalMix remote: pick another pair of ports in MixBar's Settings (e.g. 7002/9002) and set the same ports on a second Remote Controller slot in TotalMix's OSC settings. |
| MB-203 | The TotalMix host address isn't a valid IP address. | Use 127.0.0.1 when TotalMix runs on this Mac, or the other computer's IP address (like 192.168.1.20). |
| MB-204 | TotalMix isn't answering over OSC. | Make sure TotalMix FX is running, **Options → Enable OSC Control** is ticked, and the remote in **Options → Settings → OSC** uses the same host and ports as MixBar's Settings (default 127.0.0.1, port incoming 7001, port outgoing 9001). |
| MB-205 | TotalMix is answering in its old OSC mode, not Global OSC. | In TotalMix open **Options → Settings → OSC** and set **Compatibility (Mode)** to **Global OSC**. This needs TotalMix FX 2.1 or newer. |

## Volume keys and the Mono shortcut (3xx)

| Code | What happened | What to try |
|---|---|---|
| MB-301 | MixBar doesn't have Accessibility permission, so the volume keys still control macOS instead of TotalMix. | Turn MixBar on in **System Settings → Privacy & Security → Accessibility**. If it's already on, remove it with **−**, add it again, and relaunch MixBar. This is needed again after every update. |
| MB-302 | Couldn't start listening for the volume keys. | Quit and reopen MixBar. If it keeps happening, remove MixBar from Accessibility with **−**, add it again, and relaunch. |
| MB-303 | Couldn't set up the ⇧⌘M Mono shortcut. | Another app is probably using ⇧⌘M. Turn off the shortcut in MixBar's Settings, or quit the other app. |

## Login item (4xx)

| Code | What happened | What to try |
|---|---|---|
| MB-401 | Couldn't change Open at Login. | Add MixBar yourself in **System Settings → General → Login Items**. |

## Installers (6xx)

| Code | What happened | What to try |
|---|---|---|
| MB-601 | The installer couldn't copy MixBar into ~/Applications. | Check that ~/Applications exists and isn't locked, then run the installer again. |
| MB-602 | The installer couldn't sign MixBar for this Mac. | Install Apple's Command Line Tools (`xcode-select --install`) and run the installer again. |
| MB-603 | MixBar was installed but couldn't be opened. | Open MixBar from ~/Applications yourself. |

## Anything else (9xx)

| Code | What happened | What to try |
|---|---|---|
| MB-999 | Something unexpected went wrong. | Try again. If it keeps happening, copy the details and ask for help. |

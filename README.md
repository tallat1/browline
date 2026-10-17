<p align="center">
  <img src="docs/images/icon.png" width="128" height="128" alt="Browline app icon">
</p>

<h1 align="center">Browline</h1>

<p align="center">
  A dynamic notch for your MacBook: music, files, meetings, timers and your AI agents,<br>
  right where the camera lives.
</p>

<p align="center">
  <a href="https://github.com/tallat1/browline/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/tallat1/browline?include_prereleases&label=release"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-blue"></a>
</p>

<p align="center"><b>English</b> · <a href="README.tr.md">Türkçe</a></p>

<p align="center">
  <img src="docs/images/hero.png" alt="Browline's open notch showing music controls, the next meeting and a timer" width="760"><br>
  <sub>Screenshot with sample data.</sub>
</p>

> [!NOTE]
> Browline 0.9 is a public beta. It is not notarized by Apple yet, so macOS asks you to confirm the first launch.
> See [Install](#install).

## Features

**Now.** Everything that is happening, in one glance.
- Now Playing with artwork-tinted controls, a scrubbable progress bar, swipe-to-skip and a picker when several apps play at once.
- The next meeting with one-click join. Mute your microphone system-wide and jump back to the call.
- Live activities in the closed notch: music bars that react to the audio, charging, camera and microphone in use, screen recording, timers, CI runs, Bluetooth batteries and output device changes.
- An optional replacement for the system volume and brightness overlay.

**Shelf.** A drop zone at the top of your screen.
- Drop files on the notch, then AirDrop, share, zip or Quick Look them.
- Convert images to JPEG, PNG, HEIC or a smaller size, and videos to 1080p or 720p MP4 or audio only. No ffmpeg needed.
- Drag the screenshot thumbnail from the corner of the screen straight in.
- Clipboard history: the last 50 copies, kept in memory only. Items that password managers mark as concealed are never recorded.

**Calendar.** Today's events and reminders; tick reminders off from the notch.

**Tools.** Timer and Pomodoro, a quick note, a mirror, a full terminal and keep-awake.

**Status.**
- System: ten-minute CPU, memory and network charts, plus the battery of your Bluetooth devices.
- Claude Code plan usage and limit resets (opt-in), also when you use Claude Code in the Claude desktop app. Browline asks your installed Claude Code for `/usage` and never reads your Claude sign-in.
- GitHub Actions runs for the repositories you choose, through your own `gh` CLI.

**For developers and AI agents.**
- Push your own live activities with the `notch` command-line tool, the `browline://` URL scheme or Shortcuts actions.
- Claude Code hooks show "working", "waiting for you" and "done" per session. You can also answer Claude Code permission prompts from the notch.
- A Codex CLI example is included.

**Fits your Mac.**
- Per display: the notch, a menu bar pill on displays without a notch, a floating card, or off.
- Hides in full screen, Mission Control and games. Shows a compact strip on the lock screen.
- Follows Reduce Motion and Low Power Mode. About 0.05% CPU when idle.
- English and Turkish.

## Requirements

- macOS 14 Sonoma or later.
- Best on a MacBook with a notch. Displays without one get a pill or a floating card.
- Universal app (Apple silicon and Intel). Developed and tested on macOS 27 on Apple silicon; macOS 14, 15 and 26 and Intel are supported by the code but not tested yet. [Reports are welcome](https://github.com/tallat1/browline/issues).

## Install

1. Download `Browline-0.9.0.dmg` from the [latest release](https://github.com/tallat1/browline/releases/latest) and drag Browline to Applications.
2. Open Browline. Because the beta is not notarized, macOS blocks the first launch:
   - **macOS 15 and later:** open System Settings › Privacy & Security, scroll down to "Browline was blocked…" and click **Open Anyway**.
   - **macOS 14:** Control-click Browline in Applications, choose **Open**, then **Open** again.
3. Browline lives in the menu bar; it has no Dock icon. A short welcome asks how you want to use the notch.

Permissions are requested only when you turn on a feature that needs them. Settings › Permissions lists every one with its state.

**Updates.** From 0.9.1 on, Browline updates itself with [Sparkle](https://sparkle-project.org): on the second launch it asks whether to check automatically, and every update is verified with Browline's signing key before it's installed. Settings › General has the switch and a Check Now button. 0.9.0 has to be updated by hand from the releases page.

To verify the download, compare `shasum -a 256 Browline-0.9.0.dmg` with the checksum in the release notes.

## Using Browline

- **Open:** hover over the notch and it opens after a short delay (adjustable in Settings › Notch); move away and it closes. Click it, or scroll down on it, to open it and keep it open. Press Esc, click elsewhere or scroll up to close.
- **Sections:** Now, Shelf, Calendar, Tools and Status sit in the notch's top bar.
- **Settings:** menu bar icon › Settings… (⌘,). Search finds any option.
- **Microphone:** ⌃⌥M mutes or unmutes the microphone in any app. You can change the shortcut in Settings.

## Activity API

Scripts, build tools and agents can show their own live activity in the notch.

```sh
notch push  --id build --title "Building" --progress 40% --symbol hammer --tint "#FF9F0A"
notch end   --id build
notch flash --title "Build passed" --symbol checkmark.circle.fill --tint "#34C759" --duration 3
```

Turn on Settings › Now › Script and AI agent activities first. The tool is inside the app: `/Applications/Browline.app/Contents/Helpers/notch`. The same operations also work as URLs, which suits Raycast, Alfred and Shortcuts. Web pages can open these links too, so `browline://` links have their own switch, off by default:

```sh
open -g "browline://push?id=build&title=Building&progress=40%25&symbol=hammer"
```

Shortcuts also gets three native actions: show an activity, end an activity and show a brief notice. Everything runs over a local Unix socket that only your user account can open. Details and limits are in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md#etkinlik-apisi) (Turkish).

### Claude Code and Codex

[`Examples/`](Examples) contains ready-made hooks:

- **Claude Code status:** merge the `hooks` from [`Examples/claude-code/settings-hooks.json`](Examples/claude-code/settings-hooks.json) into `~/.claude/settings.json` and set the script path.
- **Permission prompts:** the `PermissionRequest` entry in the same file opens the notch with the tool, project and full command, and offers Allow or Deny for that single request.
  - A decision only ever comes from your click.
  - No permanent rule is ever written.
  - If you don't answer, Claude Code falls back to its own prompt. If you answer in Claude itself, the notch copy disappears as soon as the tool runs.
- **Multiple-choice questions:** when Claude asks you to pick between options, the same hook shows them in the notch. Click one (or tick several and press Send) and the answer goes straight back to Claude. Answer in Claude leaves the question to Claude's own window, for example to type your own answer.
- **Decision boxes (Claude desktop app):** when a turn ends with a question and buttons in the Claude desktop app, the `Stop` hook shows a "Claude is waiting for you" card with the question, the summary and the same buttons. Click one and Browline clicks the matching button in Claude for you, so the reply goes out as your own message. Claude doesn't let other apps send messages into a session, so this needs the Accessibility permission. If it's missing, the card shows how to grant it: Allow… opens the right Privacy & Security pane and shows Browline in Finder, so you can drag it into the list (on macOS 27 the app doesn't appear there by itself). If the button can't be found unambiguously, Browline just opens the session. Answer in Claude opens the session so you can type your own answer. The card goes away when you send your next message.
  - Settings › Now turns permission prompts, multiple-choice questions and decision boxes on or off separately.
- **Codex CLI:** set `notify = ["/bin/bash", "/path/to/Examples/codex/notch-notify.sh"]` in `~/.codex/config.toml`.

## Privacy

- **No accounts, analytics or telemetry.** The only connection Browline makes on its own is the update check, and only if you allow it.
- **Your data stays local.** Settings, the shelf list and notes live in `~/Library/Application Support/com.talatozcoban.browline`. Clipboard history stays in memory and is gone when you quit.
- **Claude limits** (opt-in) run your installed `claude` command with `/usage`: every 5 minutes while a Claude Code session is working, every 30 minutes otherwise. Claude Code answers with its own sign-in, which Browline never sees, and no model is used. Browline also reads the account name from `~/.claude.json` and limit notices in Claude Code's session logs.
- **Network access only for features you turn on:**

| Feature | Talks to | Sends |
|---|---|---|
| Weather | [Open-Meteo](https://open-meteo.com) | The coordinates of the city you pick, not your location |
| CI status | GitHub, through your own `gh` CLI | Nothing from Browline itself; `gh` uses its own sign-in |
| Claude limits | Anthropic, through your own `claude` CLI | Nothing from Browline itself; Claude Code uses its own sign-in |
| Updates | GitHub (the release list and downloads) | Nothing beyond the request itself, which includes the app version |

**Permissions.** Each one is asked only when its feature is on:

| Permission | Used for |
|---|---|
| Calendars, Reminders | Today's events and reminders |
| Camera | Mirror, only while it is open |
| System audio recording | Music bars that react to the audio. Nothing is recorded or saved. |
| Automation | Controlling Music and Spotify when the system media service is unavailable |
| Accessibility | Replacing the system volume and brightness overlay, and clicking a Claude decision button you chose in the notch (both optional) |
| Paste from other apps | Clipboard history (optional) |

## Undocumented APIs

Where macOS has no public API, Browline uses private ones. Each is looked up at runtime, and the feature turns itself off if the symbol is missing. A macOS update can break these features, and they are why Browline cannot ship in the Mac App Store.

| Feature | API |
|---|---|
| Now Playing on macOS 15.4 and later | MediaRemote, through [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) |
| Brightness overlay | DisplayServices |
| Screen recording indicator | SkyLight `CGSIsScreenWatcherPresent` |
| Lock screen panel (experimental, off by default) | SkyLight spaces |

## Build from source

You need Xcode 26 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and CMake:

```sh
brew install xcodegen cmake
git clone https://github.com/tallat1/browline.git
cd browline
make run                                          # build the helpers, generate the project, build and launch
make run XCODE_FLAGS='DEVELOPMENT_TEAM=ABCDE12345' # sign with your own team
make test                                         # unit tests
```

A stable signing identity keeps macOS permissions across rebuilds. Ad-hoc signing (`XCODE_FLAGS='CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM='`) works, but macOS asks for every permission again after each build. `Scripts/release.sh` builds the universal, hardened-runtime DMG.

| Path | What's inside |
|---|---|
| `App/` | The app, organized by feature: `Core` (coordinator, navigation, settings), `Notch` (closed and open notch), `Features/<feature>`, `DesignSystem`, `Settings`, `Application`; see [ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| `Packages/NotchCore/` | Swift package: panel and geometry (`NotchShell`), activity priority (`ActivityEngine`), system integrations (`Integrations`), socket protocol (`ActivityAPI`), private API bridges (`PrivateBridges`) |
| `CLI/` | The `notch` command-line tool |
| `Helpers/`, `ThirdParty/` | Now Playing helpers |
| `Examples/` | Claude Code and Codex hooks |
| `docs/ARCHITECTURE.md` | Modules, data flow, conventions and how to add a feature |
| `docs/DEVELOPMENT.md` | Engineering notes, measurements and design decisions (Turkish) |

## Roadmap

- Developer ID signing and notarization for 1.0
- Testing on macOS 14, 15 and 26 and on Intel Macs
- Focus mode

## Contributing

Bug reports, ideas and pull requests are welcome; please open an [issue](https://github.com/tallat1/browline/issues) first for larger changes. Browline is a clean-room project: please don't contribute code copied from other notch apps, several of which are GPL-licensed.

## Acknowledgements

- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) by Jonas van den Berg (BSD 3-Clause)
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) by Miguel de Icaza (MIT)
- [Sparkle](https://sparkle-project.org) by the Sparkle Project (MIT)
- Ideas from the notch app community: NotchNook, Alcove, boring.notch, Atoll, DynamicLake, MediaMate and others. Browline contains none of their code.

Full license texts: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

[MIT](LICENSE) © 2026 Talat Özçoban

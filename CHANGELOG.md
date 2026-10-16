# Changelog

All notable changes to Browline are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org).

## [Unreleased]

### Changed
- The `notch` command-line tool and the activity API answer in English or Turkish, following the first language in your system's language list.

## [0.9.0] - 2026-10-16

First public beta.

### Added
- Dynamic notch with five sections: Now, Shelf, Calendar, Tools and Status.
- Now Playing with artwork-tinted controls, scrubbing, swipe-to-skip, a multi-app picker and music bars that react to the audio.
- Meetings: the next event with one-click join, a system-wide microphone mute (⌃⌥M) and "return to call".
- Live activities in the closed notch: charging, camera and microphone in use, screen recording, timers, CI runs, Bluetooth devices, audio output changes, battery alerts and an optional volume and brightness overlay.
- Shelf with AirDrop, sharing, zip, Quick Look and image and video conversion; screenshot thumbnails can be dropped in directly.
- Clipboard history kept in memory only.
- Calendar events and reminders; timer and Pomodoro, quick note, mirror, terminal and keep-awake.
- System charts for CPU, memory and network; Claude Code plan usage from its status line; GitHub Actions status through `gh`.
- Activity API: the `notch` CLI, the `browline://` URL scheme and Shortcuts actions; Claude Code and Codex examples, including answering Claude Code permission prompts from the notch.
- Per-display modes (notch, pill, floating card), hiding in full screen, Mission Control and games, and a lock screen strip.
- Settings with a sidebar, search and an in-app permissions page; a short welcome with usage profiles.
- English and Turkish.

### Known issues
- Not notarized: macOS asks you to confirm the first launch (see the README).
- Tested on macOS 27 on Apple silicon only.
- No automatic updates yet; watch the GitHub releases.

[0.9.0]: https://github.com/tallat1/browline/releases/tag/v0.9.0

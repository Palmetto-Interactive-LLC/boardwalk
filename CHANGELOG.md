# Changelog

All notable changes to Boardwalk are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-10-20

### Added

- Workout timer that counts walking time only while the belt moves, with a Reset button.
- Estimated calories burned (ACSM walking equation) using a body weight you set once.
- Time-of-day clock in the window.
- Menu bar shows walking time next to speed while the belt is moving.

## [1.0.0] - 2026-10-12

First public release.

### Added

- On, Off, faster, slower and set-speed controls for Bluetooth FTMS treadmills.
- Live speed in mph and km/h.
- Automatic connect and reconnect, plus a manual Connect / Disconnect button.
- Start speed of 1.4 mph, applied after the treadmill's start-up countdown.
- Menu bar item showing the current speed.
- `boardwalk://` links for Shortcuts and other automation tools.
- One-time safety notice on first launch.
- `setup.sh` to build, install and launch, with a stable local signing identity so Bluetooth permission survives rebuilds.
- Protocol notes for the YIJIAN ZBJ_38A_BT controller in `docs/PROTOCOL.md`.

[1.1.0]: https://github.com/Palmetto-Interactive-LLC/boardwalk/releases/tag/v1.1.0
[1.0.0]: https://github.com/Palmetto-Interactive-LLC/boardwalk/releases/tag/v1.0.0

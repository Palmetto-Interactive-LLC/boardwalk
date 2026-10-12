# Contributing to Boardwalk

Thanks for helping out. Boardwalk is deliberately small, so the best contributions keep it that way.

## Compatibility reports

The most useful thing you can send is a report on whether Boardwalk works with your treadmill. Open a [compatibility report](../../issues/new?template=compatibility-report.md) with the model, what worked, and what didn't. Attaching `~/Library/Logs/Boardwalk.log` helps a lot.

## Bugs and ideas

Open an issue with what you expected, what happened, your macOS version, and your treadmill model. For anything bigger than a small fix, open an issue before writing code so we can agree on the approach.

## Pull requests

1. Fork the repo and branch from `main`.
2. Keep the change focused. One fix or feature per pull request.
3. Build it with `./scripts/build.sh`, and if you can, test on a real treadmill with the belt clear.
4. Say in the pull request which treadmill you tested on, or that you couldn't test on hardware.
5. Add a line to `CHANGELOG.md` under an `Unreleased` heading.

CI builds every pull request on macOS. Please make sure it's green before asking for a review.

## Code guidelines

- The whole app lives in `Sources/Boardwalk.swift`. Please keep it a single file with no third-party dependencies unless there's a strong reason.
- It builds with `swiftc` and the Command Line Tools alone, without an Xcode project. Don't use SwiftUI features that need Xcode-only macro plugins, such as `@State` and `@Observable` on the current SDK. Keep view state in the `ObservableObject` model instead.
- Treadmill firmware is quirky. If you work around a behavior, document what you measured in `docs/PROTOCOL.md`.
- Anything that can move the belt needs extra care. Never start the belt or raise its speed without an explicit user action.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).

# Security Policy

Boardwalk runs entirely on your Mac. It talks to your treadmill over Bluetooth and makes no network connections. Even so, it controls physical equipment, so please report anything that could let someone start the belt or change its speed without the user meaning to.

## Reporting a vulnerability

Please don't open a public issue for a suspected vulnerability. Use GitHub's [private vulnerability reporting](../../security/advisories/new) for this repository instead. Include the affected version, steps to reproduce, and the impact.

We'll acknowledge the report, work on a fix, and credit you in the release notes unless you'd rather stay anonymous.

## Supported versions

| Version | Supported |
| --- | --- |
| `main` | Yes |
| Latest release | Yes |
| Older releases | No |

## Worth knowing

- Any app or web page on your Mac can open a `boardwalk://` link, and that's how Shortcuts integration works. It means local software can start the belt. Keep that in mind before using Boardwalk on a shared or untrusted machine.
- `setup.sh` creates a self-signed **Boardwalk Local Signing** certificate in your login keychain. It's only used to sign the app locally and never leaves your Mac.

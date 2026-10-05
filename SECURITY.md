# Security Policy

## Reporting a vulnerability

Please do not report security vulnerabilities in public issues, pull requests, or discussions. Use GitHub's **Report a vulnerability** feature on the repository's Security tab when it is available, or email [svitlobot@gmail.com](mailto:svitlobot@gmail.com) with the subject `SvitloBot iOS security report`.

Include the affected version or commit, the impact, steps to reproduce, and any proposed mitigation. Do not include real Telegram bot tokens, channel keys, personal data, or other production secrets. A minimal sanitized proof of concept is preferred.

The repository currently has a single maintainer. Reports are reviewed as capacity allows; no response or remediation deadline is promised. Please allow time for investigation and coordinated disclosure before publishing details. There is no bug bounty program.

If a credential was exposed, revoke or rotate it with its provider immediately. For a Telegram bot token, use BotFather; for a channel key, contact the service that issued it.

## Supported versions

Security fixes are made against the current maintained source on the default branch. Users should install the latest available app version and keep iOS or iPadOS updated.

## Scope

This policy covers the SvitloBot iOS source repository and the iOS application built from it. The SvitloBot service, Telegram, Apple platforms, and third-party infrastructure have separate operators and reporting channels.

See [THREAT_MODEL.md](THREAT_MODEL.md) for application boundaries and known risks, and [docs/REPOSITORY_SECURITY.md](docs/REPOSITORY_SECURITY.md) for GitHub controls that must be enabled in repository settings.

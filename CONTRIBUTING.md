# Contributing

Thanks for helping improve SvitloBot for iOS. The project is maintained by one person, so small, focused contributions are easiest to review.

## Before opening an issue

- Use the issue forms for ordinary bug reports and feature requests.
- Search existing issues first and include the app version, iOS/iPadOS version, device model, and clear reproduction steps where relevant.
- Remove personal information, Telegram bot tokens, channel keys, and private channel identifiers from logs and screenshots.
- For a suspected vulnerability, follow [SECURITY.md](SECURITY.md); do not file a public issue.

## Pull requests

1. Fork the repository or create a short-lived branch from `main`.
2. Keep each pull request focused and explain the user-visible effect and any security or privacy impact.
3. Update user-facing documentation and privacy disclosures when data flows or behavior change.
4. Run the checks appropriate to the change and describe what you ran. The app's signed build and distribution remain in Xcode Cloud.
5. Do not add secrets, provisioning profiles, signing certificates, production credentials, or private user data.
6. Include screenshots for meaningful UI changes, with sample data only.

There is no committed automated test target at this time. Do not describe an Xcode Cloud build, test, or release as complete unless its run confirms that result.

## Swift style

The repository includes Apple's `swift-format` configuration. Format Swift files you change with:

```sh
xcrun swift-format format --in-place --configuration .swift-format path/to/File.swift
xcrun swift-format lint --configuration .swift-format path/to/File.swift
```

The existing application source predates this formatter configuration. Its initial workflow reports formatting diagnostics while the existing baseline is migrated; it does not reformat application files automatically.

## Review and release

The maintainer reviews changes, checks the Xcode Cloud result when relevant, and decides whether and when to release. Do not create or move release tags on behalf of the maintainer.

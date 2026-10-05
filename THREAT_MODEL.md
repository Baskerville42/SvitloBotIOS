# Threat Model

**Scope:** SvitloBot for iOS, as represented by the current repository source. This document describes the application client; it does not assess the SvitloBot backend, Telegram, Apple operating systems, Xcode Cloud, or GitHub infrastructure.

Review this model whenever an endpoint, credential, persistence mechanism, permission, dependency, or release path changes.

## Security objectives

- Keep user-provided Telegram bot tokens and channel keys out of source control, public reports, and routine diagnostics.
- Send network traffic only to the configured SvitloBot service and Telegram Bot API over HTTPS.
- Make it clear that charging status is an approximate signal, not an authoritative measurement or safety control.
- Keep changes and release artifacts attributable to a reviewed source revision.

## Assets and data

| Asset | Current handling |
| --- | --- |
| Telegram bot token | Stored in the iOS Keychain; sent to Telegram as part of the HTTPS Bot API request URL. |
| SvitloBot channel key | Stored in app preferences and sent to the SvitloBot API as a query parameter. |
| Telegram destination | Stored in app preferences and sent to Telegram with API requests. |
| Charging events and queued Telegram messages | Persisted locally by the app so the event log and offline delivery queue can work. |
| Network metadata | The receiving service necessarily sees connection metadata such as source IP address; handling is governed by that service's policy. |
| Source, workflow definitions, and signing configuration | Maintained in GitHub and Xcode Cloud. Signing material must not be committed or copied into GitHub Actions. |

## Trust boundaries and flows

1. **SvitloBot mode:** the app sends a channel key and a monitoring signal to the SvitloBot API. The backend determines status and may publish to its Telegram channel.
2. **Telegram-fallback mode:** the app sends charging-transition message text and a destination to Telegram Bot API using the user's bot token. Failed sends may be queued locally and retried when connectivity returns.
3. **Local storage:** settings, event history, and pending delivery data remain on the device. The Telegram token is stored separately in Keychain.
4. **Build and documentation:** GitHub Actions perform code scanning, repository scoring, formatting diagnostics, and GitHub Pages publication. App signing and distribution stay in Xcode Cloud.

## Threats and mitigations

### Credential exposure

**Threat:** a bot token or channel key is copied into a screenshot, issue, log, commit, or diagnostic report.

**Current safeguards:** the Telegram token is stored in Keychain; repository templates warn against posting secrets; GitHub secret scanning and push protection are recommended in [the repository security checklist](docs/REPOSITORY_SECURITY.md).

**Residual risk:** the channel key is stored in regular app preferences and appears in the SvitloBot API query string. Request errors are written to the device console. Review or redact diagnostics before sharing them. A Telegram bot token appears in the Bot API URL path because that is how Telegram's API authenticates bot requests; use a bot dedicated to this purpose and rotate it if exposed.

### Untrusted networks and services

**Threat:** network interception, a compromised endpoint, or a service outage reveals or alters data or prevents alerts.

**Current safeguards:** service URLs in the application use HTTPS and Apple App Transport Security is enabled for internet requests.

**Residual risk:** this client does not control service-side logging, retention, access control, channel membership, or availability. The channel key in a URL may be captured by server, proxy, or diagnostic logging. Telegram messages may be visible to channel members. Review the [privacy policy](docs/privacy-policy.html) and external providers' policies.

### Incorrect or delayed status

**Threat:** charging does not match grid availability, iOS suspends the app, or connectivity fails, resulting in a missing or delayed event.

**Mitigation and limitation:** the app explains that regular monitoring requires it to remain open. Telegram-fallback queues failed sends where possible. Neither mode is a guaranteed delivery channel or an emergency, safety, or power-control system.

### Malicious source or build workflow

**Threat:** a malicious change, compromised dependency or action, or overprivileged workflow alters the application or leaks signing credentials.

**Current safeguards:** CodeQL scans Swift and GitHub Actions; workflow actions are pinned to full commit SHAs; Scorecard evaluates repository supply-chain practices; Dependabot proposes workflow updates; GitHub Actions permissions are scoped per job.

**Residual risk:** repository account recovery, branch protection, secret scanning, private vulnerability reporting, and Xcode Cloud access controls require GitHub or Apple account settings. Follow [docs/REPOSITORY_SECURITY.md](docs/REPOSITORY_SECURITY.md).

## Security invariants

1. Never commit production bot tokens, channel keys, signing certificates, provisioning profiles, or private user data.
2. Do not add an endpoint or downgrade transport security without reviewing the privacy policy and threat model.
3. Keep app signing and distribution credentials in Xcode Cloud; GitHub Actions must not receive them.
4. Do not publish a vulnerability report before coordinating with the maintainer.
5. Treat status and delivery as best effort; never represent them as guaranteed or safety-critical.

## Out of scope

This model does not assess the server implementation, Telegram's or Apple's handling of data, the user's device compromise, or the accuracy of an external power source. It does not claim a security certification or a guarantee of vulnerability-free software.

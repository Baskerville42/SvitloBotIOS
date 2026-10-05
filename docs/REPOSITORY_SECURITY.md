# GitHub repository security setup

The repository contains the configuration files for automated checks, but GitHub account and repository settings cannot be committed. Apply the following settings after the local changes are reviewed and pushed.

## 1. Turn on reporting and dependency alerts

In **Settings → Code security and analysis**:

- Enable private vulnerability reporting so security researchers can contact the maintainer without opening a public issue.
- Enable Dependabot alerts and Dependabot security updates.
- Enable secret scanning and push protection where available.
- Enable GitHub Actions permissions needed for code scanning and Pages. The workflows declare their own narrow job permissions.

The repository is public, so GitHub's public-repository security features may be available without a paid license. Check the current repository settings page for the exact availability.

## 2. Protect the default branch for a single maintainer

Create a branch ruleset for `main`:

- Block force pushes and branch deletion.
- Require the CodeQL workflow checks to complete before merge after their first successful run.
- Require pull requests if you want a consistent review trail. Keep the required approval count at zero while you are the sole maintainer; introduce mandatory independent approval only after another maintainer can provide it.
- Do not require a signature or check tied to an unavailable external action.

Xcode Cloud may expose its own status checks. Add the relevant Xcode Cloud check only if it reliably runs for the pull requests you intend to merge. GitHub Actions do not sign, archive, or distribute the app.

## 3. Restrict Actions and token permissions

In **Settings → Actions → General**:

- Set the default `GITHUB_TOKEN` permission to read repository contents.
- Keep workflows from creating or approving pull requests unless a specific workflow needs that ability.
- Require approval for workflows from first-time contributors where GitHub offers the setting.
- Permit the pinned GitHub-owned Actions and OpenSSF Scorecard Action used here. Review every requested Action change before merging its Dependabot pull request.

No Xcode Cloud signing credential, App Store Connect key, provisioning profile, or production bot token belongs in GitHub Actions.

## 4. Secure the maintainer account

- Use a passkey or hardware-backed multi-factor authentication and store recovery codes safely.
- Review GitHub sessions, authorized OAuth applications, SSH keys, and fine-grained personal access tokens periodically.
- Keep Xcode Cloud and App Store Connect access limited to the people who need it.
- Rotate credentials immediately after suspected exposure and review recent workflow runs.

## 5. Confirm Pages configuration

Set **Settings → Pages → Build and deployment → Source** to **GitHub Actions**. The Pages workflow publishes only `docs/`; it is separate from Xcode Cloud app builds and releases.

## Ongoing review

Review CodeQL findings, Scorecard results, and Dependabot pull requests. Update the list of required status checks if workflow job names change. When an SPM, CocoaPods, or Carthage dependency is added, add its lockfile or manifest to the dependency-update and review process before adopting it.

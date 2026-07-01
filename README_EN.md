<p align="center">
  <img src="Resources/AppIcon.png" alt="Codex Runway logo" width="128" height="128">
</p>

# Codex Runway

[中文](README.md) | English

How much longer can your Codex keep running?

Codex Runway is a native macOS menu bar app for checking Codex quota, reset credits, API-equivalent cost, local sessions, and update status.

## Highlights

- Check remaining Codex quota from the menu bar.
- View 5-hour, weekly, and additional quota windows.
- Show the current Codex account and subscription tier.
- View reset credit count, status, and expiration time.
- View current-cycle API-equivalent cost and token usage.
- View recent Codex sessions, projects, status, and usage summaries.
- Repair the local session index.
- Support light, dark, system appearance, Chinese, and English.
- Support built-in update checks.

## Screenshots

<p align="center">
  <img src="docs/images/1.png" alt="Codex Runway quota overview" width="260">
  <img src="docs/images/2.png" alt="Codex Runway reset credits details" width="260">
  <img src="docs/images/3.png" alt="Codex Runway API-equivalent cost" width="260">
  <img src="docs/images/4.png" alt="Codex Runway setting page" width="260">
  <img src="docs/images/5.png" alt="Codex Runway sessions" width="260">
</p>

## Installation

Download the matching zip from GitHub Releases:

- Apple Silicon: `CodexRunway-macos-arm64.zip`
- Intel: `CodexRunway-macos-x86_64.zip`

Unzip it and place `CodexRunway.app` in `Applications` or any folder you prefer.

### macOS Security Blocks

Current releases are ad-hoc signed and not notarized. If macOS says the developer cannot be verified or the app was not checked for malicious software, right-click `CodexRunway.app` and choose Open, or go to System Settings > Privacy & Security and click Open Anyway.

If macOS says `CodexRunway.app` is damaged and should be moved to the Trash, it is usually the download quarantine attribute. After placing the app in `Applications`, run:

```bash
xattr -dr com.apple.quarantine /Applications/CodexRunway.app
```

Then open the app again.

## Requirements

- macOS 12+
- A local Codex login
- `~/.codex/auth.json` exists on this Mac

## Run Locally

```bash
swift run CodexRunway
```

Self-check:

```bash
swift run CodexRunway --self-check
```

The self-check prints local diagnostics with tokens redacted.

## Privacy

- Tokens are read only from local `~/.codex/auth.json`.
- Access tokens, refresh tokens, and ID tokens must not be written to logs, README files, issue templates, or self-check output.
- API-equivalent cost is computed from local session JSONL logs by default and does not upload session contents.
- Online usage data is used only when local token data is unavailable.
- Session repair only touches `~/.codex/session_index.jsonl`, creates a backup before writing, and never deletes session files.
- Update checks request only version information. Codex account and session data are not uploaded.

## Development and Contribution

```bash
swift test
swift build
swift build -c release
```

See [CONTRIBUTORS.md](CONTRIBUTORS.md) for contribution notes.

## License

This project follows the repository [LICENSE](LICENSE).

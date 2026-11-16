# Contributing

Use native Swift and AppKit, with macOS 13 as the minimum target. Keep the app independent of a particular user's paths, installed Python, and shell initialization files.

Run `bash scripts/test.sh` and `bash scripts/build.sh` before opening a pull request. Lifecycle changes also need a real agentmemory smoke test: start, authenticated health, stop, restart, saved stop preference, and app launch at login.

Do not add recurring polling or automatic server restarts without an explicit product decision. Do not log authentication headers, `.env` contents, or captured memory. Use argument arrays rather than shell interpolation for external processes. Control processes through the upstream CLI; never use broad process-name kills.

The UI controller queue serializes work. The file lock also coordinates command-line invocations. File watchers must not react endlessly to their own status-check temporary files.

For bugs, include macOS/architecture, agentmemory version, the menu's status, and redacted reproduction details. Security reports should omit credentials and private session data.

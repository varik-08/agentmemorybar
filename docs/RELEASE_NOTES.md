Native macOS menu bar companion for [agentmemory](https://github.com/rohitg00/agentmemory).

Download the DMG, drag AgentMemoryBar into Applications, and open it from there. Requires macOS 13+, Node.js 20+, and an initialized agentmemory installation. The app includes Apple Silicon and Intel slices; runtime testing has been performed on Apple Silicon only.

- Start, stop, restart, and authenticated health status.
- Optional launch at login: the app starts the server when enabled.
- Saved stop preference; no polling timer or automatic recovery loop.
- Viewer shortcut, settings, and logs.

This CI build is ad-hoc signed, **not notarized by Apple**. Verify SHA256SUMS and follow the README's opening instructions. agentmemory itself is not bundled.

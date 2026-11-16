# Releasing AgentMemoryBar

## First publication

Create an empty public GitHub repository named `agentmemorybar`, then push this local repository and create the first release tag:

```sh
git add .
git commit -m "Initial AgentMemoryBar release"
git tag v0.1.0
git remote add origin git@github.com:YOUR-USER/agentmemorybar.git
git push -u origin main
git push origin v0.1.0
```

The tag workflow builds a universal app, runs controller checks, creates a DMG with an Applications shortcut, verifies it, and uploads the DMG and SHA256SUMS to a **draft GitHub Release**. Review the assets and notes, then publish the release.

No GitHub repository or release is created by the local build. The workflow runs only after upload. Its default build is ad-hoc signed and not notarized; release notes disclose this.

## Next version

1. Update `VERSION` and `CHANGELOG.md`.
2. Run `bash scripts/test.sh`, `bash scripts/build.sh`, and `bash scripts/dmg.sh`.
3. Install the app outside the mounted DMG and smoke-test status, stop, start, restart, quit, and login behavior. Check that no separate server job or minute interval is enabled.
4. Commit, create a matching `vX.Y.Z` tag, and push the commit and tag.
5. Review the draft and publish it. Do not replace binaries under an existing version tag.

The workflow can also be dispatched manually with a tag that already exists. It rejects tags that do not match `VERSION`.

## Developer ID signing (local)

An Apple Developer ID Application certificate and a configured notarytool Keychain profile are required:

```sh
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' bash scripts/build.sh
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
  NOTARY_PROFILE='agentmemorybar-notary' bash scripts/dmg.sh
```

`build.sh` signs with hardened runtime and a secure timestamp. `dmg.sh` signs the image, submits it to Apple, staples the ticket, and then calculates its checksum. Neither certificates nor credentials belong in the repository.

The included public GitHub workflow intentionally has no signing credentials. Add a dedicated protected signing job if you want notarized CI releases. Do not describe an ad-hoc build as Apple-verified. See [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

# Release Process

## Versioning
Use semantic tags: `vMAJOR.MINOR.PATCH`.

Release automation treats the git tag as the source of truth for `MARKETING_VERSION`.
Release automation derives `CURRENT_PROJECT_VERSION` from one shared build-number formula: `git_commit_count * 10 + channel_rank`.
Stable uses channel rank `8`; Tip uses channel rank `1`. That makes a stable release from the same commit newer than its tip build, while the next main-branch tip build becomes newer again.
For local packaging, let `scripts/package_release.sh` compute the build number or pass `--build-number` / `SUNIYE_BUILD_NUMBER` for an explicit override.
Do not manually bump app version metadata in `project.yml` just to cut a release tag.

Release packaging always uses the default Stable app identity: `Suniye.app`, bundle id `dev.suniye.app`, and Sparkle release updates enabled. Local development builds that need to coexist with Stable should use `./scripts/build_app.sh Debug --preview --install-user --open`, which produces `Suniye Preview.app` with bundle id `dev.suniye.app.preview` and Sparkle release updates disabled. Do not publish Preview artifacts as official releases.

## Prerelease checklist
1. PR description and commits reflect the release changes accurately.
2. User-facing docs are updated for onboarding, settings, and supported model changes (`README.md`, `docs/*`).
3. `./scripts/doctor.sh` passes.
4. `./scripts/setup_llama_cpp.sh` has staged `Suniye/LocalLLM/llama-server` for Local Gemma.
5. `./scripts/e2e_preflight.sh` passes.
6. `./scripts/e2e_smoke.sh` passes.
7. `SUNIYE_CODESIGN_IDENTITY="Developer ID Application: <name> (<team-id>)" SUNIYE_NOTARY_KEYCHAIN_PROFILE=suniye-notary ./scripts/package_release.sh --version <version> --build-channel stable` runs locally.
8. `./scripts/verify_release.sh --dist-dir dist --version <version> --build-channel stable` passes.
9. Third-party license/redistribution verification completed (`THIRD_PARTY_NOTICES.md`).
10. If the ASR catalog changed, verify the supported model names and download assets still match the published sherpa-onnx artifacts.

## Publish
1. Create and push tag:
```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```
2. GitHub Actions `release.yml` asks GitHub to generate release notes for the tag, embeds them in the Sparkle appcast, injects the tag version, computes the stable build number, builds artifacts, and creates the release.

## Tip builds
Every push to `main` publishes a mutable prerelease/tag named `tip`.

The Tip workflow packages the latest `main` commit with:
```bash
./scripts/package_release.sh \
  --version <latest-tag> \
  --build-channel tip \
  --appcast-channel tip \
  --download-url-prefix https://github.com/kishanhitk/suniye/releases/download/tip/
```

The Tip appcast is served from `https://suniye.kishans.in/appcast-tip.xml`.
Both Stable and Tip appcasts must include Sparkle release notes, either as an embedded `<description>` or a `<sparkle:releaseNotesLink>`.

## Artifacts
- `Suniye.dmg`
- `Suniye.app.zip`
- `SHA256SUMS.txt`
- `appcast.xml`

## Sparkle signing key
GitHub Actions stores the Sparkle private key in `SPARKLE_PRIVATE_KEY`, but GitHub secrets are write-only and cannot be retrieved later.

The local owner copy is stored in the macOS Keychain under Sparkle account `suniye`. To export it from a Sparkle distribution:
```bash
./bin/generate_keys --account suniye -x ./suniye-sparkle-private-key
```
Move the exported file to a password manager or another secret store, then delete the local export.

## Code signing and notarization
Stable and Tip releases are signed with the Apple Developer ID Application identity of the Suniye Apple Developer team, with the hardened runtime and a secure timestamp, and notarized by Apple.

`scripts/package_release.sh` runs these steps in this order:
1. `scripts/build_app.sh --release-sign` builds the app, then `scripts/sign_release_app.sh` signs every nested binary and the app inside-out. The app gets only the entitlements in `Suniye/Suniye.entitlements` (`com.apple.security.device.audio-input`, which the hardened runtime needs for microphone capture).
2. `scripts/verify_release_signing.sh` checks the Developer ID authority, the Team ID, the hardened runtime and the secure timestamp on every Mach-O, and the exact entitlements.
3. `scripts/notarize_artifact.sh` notarizes a zip of the app, then `stapler` staples the ticket to the app.
4. The script creates `Suniye.app.zip` and `Suniye.dmg` from the stapled app, signs the DMG, notarizes it, and staples it.
5. Only then does it write `SHA256SUMS.txt` and the Sparkle appcast. Stapling changes the DMG, so the EdDSA signature must cover the stapled file. If it does not, every installed copy rejects the update.

`scripts/verify_release.sh` checks the stapled tickets, the Gatekeeper assessment (`source=Notarized Developer ID`) of the DMG and both apps, and the appcast EdDSA signature against the app's own `SUPublicEDKey`.

### Developer ID certificate
Only the Account Holder of the Apple Developer team can create it.
1. In Xcode, open **Settings > Accounts**, select the team, and choose **Manage Certificates**.
2. Add a **Developer ID Application** certificate. Use a certificate whose private key is in your login keychain. A cloud-managed certificate has no private key that you can export for CI.
3. In Keychain Access, export the identity with its private key as a password-protected `.p12`. Store the `.p12` and the password in a password manager.
4. Generate the GitHub secret value:
```bash
base64 -i Suniye-Developer-ID.p12 | tr -d '\n' | pbcopy
```

### Notary API key
1. In App Store Connect, open **Users and Access > Integrations > App Store Connect API** and create a **Team** key with the Developer role. Individual keys cannot use `notarytool`.
2. Download the `.p8` file (Apple offers it only once) and note the key ID and the issuer ID.
3. For local releases, store the key in a notarytool keychain profile:
```bash
xcrun notarytool store-credentials suniye-notary --key AuthKey_<key-id>.p8 --key-id <key-id> --issuer <issuer-id>
```

### GitHub Actions secrets
- `SUNIYE_DEVELOPER_ID_P12_BASE64`: base64-encoded Developer ID `.p12`
- `SUNIYE_DEVELOPER_ID_P12_PASSWORD`: `.p12` export password
- `SUNIYE_DEVELOPER_ID_IDENTITY`: the identity name, for example `Developer ID Application: <name> (<team-id>)`
- `SUNIYE_NOTARY_API_KEY_P8`: the contents of the `.p8` file
- `SUNIYE_NOTARY_API_KEY_ID`: the API key ID
- `SUNIYE_NOTARY_API_ISSUER_ID`: the API key issuer ID

### Permissions and the signing identity
macOS ties Microphone and Accessibility grants to the app's designated requirement, which for a Developer ID app is the bundle ID plus the Team ID. Renewing or replacing the Developer ID certificate under the same team keeps the grants. Releases before the move to Developer ID were signed with a self-signed certificate, so users who update from one of those releases grant the permissions one more time.

Sparkle accepts that one identity change because the EdDSA key stays the same. Never change the EdDSA key and the signing team in the same release.

## Homebrew tap
Stable releases publish a Homebrew Cask to the custom tap `kishanhitk/homebrew-tap`, so users can `brew install --cask kishanhitk/tap/suniye`.

`release.yml` runs `scripts/update_homebrew_tap.sh` after creating the GitHub release. It renders `packaging/homebrew/suniye.rb.tmpl` (injecting the tag version and the `Suniye.dmg` checksum from `SHA256SUMS.txt`) and pushes `Casks/suniye.rb` to the tap. The app is notarized, so the cask needs no quarantine workaround.

One-time setup:
1. Create the public repo `kishanhitk/homebrew-tap` (casks live under `Casks/`). Seed the first cask by running this from a checkout with `dist/` populated by a local `package_release.sh`:
```bash
HOMEBREW_TAP_TOKEN=<token> ./scripts/update_homebrew_tap.sh --version vX.Y.Z --dist-dir dist
```
2. Create a fine-grained personal access token with **Contents: Read and write** on `kishanhitk/homebrew-tap`, then add it as the GitHub Actions secret `HOMEBREW_TAP_TOKEN`.

If `HOMEBREW_TAP_TOKEN` is unset, the release step logs a warning and exits successfully, so the rest of the release is unaffected.

Official `homebrew-cask` is not targeted yet: it requires higher repository notability.

## Update contract
Sparkle updater behavior depends on release artifact names and signed appcast metadata:
- Preferred install artifact: `Suniye.dmg`
- Fallback install artifact: `Suniye.app.zip`
- Checksum manifest: `SHA256SUMS.txt`
- Sparkle appcast: `appcast.xml`, served to the app from `https://suniye.kishans.in/appcast.xml`
- Tip appcast: `appcast.xml` on the `tip` prerelease, served to the app from `https://suniye.kishans.in/appcast-tip.xml`
- App code signing: all Stable and Tip release artifacts must use the Developer ID Application identity of the same Apple Developer team, and must be notarized.

`SHA256SUMS.txt` must include checksum lines for published artifacts, especially `Suniye.dmg`.

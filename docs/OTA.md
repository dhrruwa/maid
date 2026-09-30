# Over-the-air updates (Maid app)

The Maid app updates itself with [Shorebird](https://shorebird.dev) code push. Once the phone runs a Shorebird build, you can fix a bug or change a screen with one command, and the cook's phone picks it up on its own. You no longer send an APK over WhatsApp.

| Change | How it reaches the phone |
|---|---|
| Home layout, notices, wording | [SDUI](SDUI.md): SQL, shows on the next Home load, no build |
| Dart code: screens, logic, new SDUI block types, bug fixes | **OTA patch** (`tool/ota.sh patch`) |
| Native: new plugin, permission, app icon, `android/` or `ios/` files, Flutter upgrade | New release: `tool/ota.sh release`, then install the APK once |

A patch is downloaded in the background when the app starts (and when it comes back to the front, at most every 30 minutes). It runs from the **next** start. If the download fails, the phone keeps the current code and tries again later.

## One-time setup

```bash
export PATH="$HOME/.shorebird/bin:$PATH"   # already in ~/.zshrc for new terminals
shorebird login                            # opens the browser; free account
cd maid_app
shorebird init --display-name Maid         # creates shorebird.yaml (commit it)
tool/ota.sh release                        # builds dist/Maid.apk with the Supabase keys
```

Then install `dist/Maid.apk` on the cook's phone, the same way as before. It updates the old app in place, so she stays paired. From now on that phone takes patches.

- **Signing key:** release APKs are signed with this Mac's `~/.android/debug.keystore`. The APK on her phone today uses the same key, so it updates in place. **Back this file up.** A new key means Android refuses the update, and uninstalling the app loses the pairing.
- **Shorebird CLI:** installed in `~/.shorebird` (Shorebird 1.6.123 with Flutter 3.47.5, the same Flutter the project uses).

## Ship a change

```bash
cd maid_app
flutter test                  # and try it: flutter run --release --dart-define-from-file=../dart_defines.json
tool/ota.sh patch             # patches the latest release
```

Check it arrived: at the bottom of Home, the phone shows **"Maid 0.1.0 (1) · patch N"**. It shows the new patch after the app has been closed and opened once more.

`tool/ota.sh patch` stops with a warning when the change can't be patched (native code or asset changes). In that case:
1. bump `version:` in `pubspec.yaml`
2. run `tool/ota.sh release`
3. install the new APK once

## Roll back

In the [Shorebird console](https://console.shorebird.dev): **Maid → the release → the patch → Roll back**. Phones go back to the previous patch on their next start or two. Or fix forward with another patch.

## iPhone

`tool/ota.sh ios-release` builds a development-signed app (team `T62SGQ3LT5`), and `tool/ota.sh ios-patch` patches it. Install the release as usual:

```
xcrun devicectl device install app --device <UDID> build/ios/iphoneos/Runner.app
```

## Notes

- Always build through `tool/ota.sh`. It adds `--dart-define-from-file=../dart_defines.json`. A patch built without it would carry the placeholder Supabase key and break every call on the phone.
- `flutter run` / `flutter build` apps have no updater. For them the version line shows no patch number, and nothing else changes.
- Code: [`maid_app/lib/core/ota.dart`](../maid_app/lib/core/ota.dart) (update check and version line) and [`maid_app/tool/ota.sh`](../maid_app/tool/ota.sh).

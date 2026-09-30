import 'package:package_info_plus/package_info_plus.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

/// Over-the-air updates (Shorebird code push, see docs/OTA.md).
///
/// A build made with `shorebird release` checks for a patch every time it
/// starts and runs it from the next start. The cook's phone may keep the app
/// open for days, so [check] also looks when the app comes back to the front;
/// the patch is then ready for the next start. Plain `flutter build` / `flutter
/// run` builds have no updater: everything here quietly does nothing.
class Ota {
  static final _updater = ShorebirdUpdater();

  /// "0.1.0 (1)", or empty until [init] has run.
  static String version = '';

  /// The patch this app is running, or null (none, or not a Shorebird build).
  static int? patch;

  /// A newer patch is downloaded and runs from the next start.
  static bool downloaded = false;

  static DateTime? _lastCheck;

  static Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version} (${info.buildNumber})';
    } catch (_) {}
    if (!_updater.isAvailable) return;
    try {
      patch = (await _updater.readCurrentPatch())?.number;
    } catch (_) {}
  }

  /// Download a new patch if there is one. At most every 30 minutes.
  static Future<void> check() async {
    if (!_updater.isAvailable || downloaded) return;
    final now = DateTime.now();
    if (_lastCheck != null && now.difference(_lastCheck!) < const Duration(minutes: 30)) return;
    _lastCheck = now;
    try {
      final status = await _updater.checkForUpdate();
      if (status == UpdateStatus.outdated) {
        await _updater.update();
        downloaded = true;
      } else if (status == UpdateStatus.restartRequired) {
        downloaded = true;
      }
    } catch (_) {
      // No network or a failed download: try again next time.
    }
  }

  /// "0.1.0 (1) · patch 3": which build and patch this phone runs.
  static String get label =>
      [if (version.isNotEmpty) version, if (patch != null) 'patch $patch', if (downloaded) '↻'].join(' · ');
}

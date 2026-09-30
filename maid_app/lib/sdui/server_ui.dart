import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../core/i18n.dart';
import 'blocks.dart';
import 'default_ui.dart';

/// Server-driven UI (docs/SDUI.md): which blocks each screen shows, in which
/// order, and text overrides for the app's strings.
///
/// Built-in bundle ([defaultUi]) → last bundle from the server (saved, so it
/// shows instantly and offline) → fresh one from get_ui.
class ServerUi {
  /// Newest block schema this app understands. Raise it when adding block
  /// types or props, and give bundles that use them the same `schema` in
  /// app_ui: the server then only sends them to apps that can show them.
  static const schema = 1;

  static Map<String, dynamic>? _server;
  static bool _loaded = false;

  /// Goes up whenever what the screens should show changes.
  static final changes = ValueNotifier<int>(0);

  static const _body = {'schema': schema};

  /// Takes the saved bundle (and its text overrides). Instant; call once
  /// Device and L are ready. [blocks] calls it too if nobody did.
  static void load() {
    if (_loaded) return;
    _loaded = true;
    // No [changes] here: this can run inside a build, before anything is shown.
    _apply(Api.cached('get_ui', _body)?['ui'], notify: false);
  }

  /// Fetches the latest bundle. True when it changed what is shown.
  static Future<bool> refresh() async {
    load();
    try {
      final r = await Api.fetch('get_ui', _body);
      return _apply(r['ui']);
    } on ApiError {
      return false; // offline, or get_ui not deployed yet: keep what we have
    }
  }

  static bool _apply(Object? ui, {bool notify = true}) {
    final next = ui is Map ? Map<String, dynamic>.from(ui) : null;
    if (jsonEncode(next) == jsonEncode(_server)) return false;
    _server = next;
    L.setOverrides(next?['strings']);
    if (notify) changes.value++;
    return true;
  }

  /// The blocks of [screen]: the server's, or the built-in ones when the
  /// server has none for it or leaves out a block in [required] (e.g. Home
  /// without Scan QR would leave the cook stuck).
  static List<UiBlock> blocks(String screen, {Set<String> required = const {}}) {
    load();
    final server = UiBlock.list(_screen(_server, screen));
    if (server.isNotEmpty && required.every((t) => UiBlock.contains(server, t))) return server;
    return UiBlock.list(_screen(defaultUi, screen));
  }

  static Object? _screen(Map? bundle, String screen) {
    final screens = bundle?['screens'];
    final s = screens is Map ? screens[screen] : null;
    return s is Map ? s['blocks'] : null;
  }

  /// For tests: forget the server bundle; the next use reads the saved one again.
  @visibleForTesting
  static void reset() {
    _server = null;
    _loaded = false;
    L.setOverrides(null);
  }

  /// For tests: use [ui] as if get_ui had sent it.
  @visibleForTesting
  static bool debugApply(Object? ui) {
    _loaded = true;
    return _apply(ui);
  }
}

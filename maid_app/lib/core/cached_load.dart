import 'package:flutter/widgets.dart';

import 'api.dart';

/// For screens that show the last saved reply straight away and refresh it in
/// the background (instant on slow phones and slow networks).
///
/// Call [load] from initState, pull-to-refresh and Retry. [data] is null only
/// while nothing is saved yet (show a spinner, or [error] if that load failed).
/// Once something is on screen it stays there: a failed refresh only sets
/// [stale] (show "showing saved information").
mixin CachedLoad<T extends StatefulWidget> on State<T> {
  Map<String, dynamic>? data;
  String? error;
  bool stale = false;

  String? _shownKey;
  int _seq = 0;

  /// Called with each fresh reply from the server (not with saved ones).
  void onFresh(Map<String, dynamic> fresh) {}

  /// False when only the server's latest reply may be shown (e.g. right after
  /// a scan, where a saved week would not have it yet).
  bool get showSaved => true;

  Future<void> load(String fn, [Map<String, dynamic> body = const {}]) async {
    final seq = ++_seq;
    final key = ApiCache.keyFor(fn, body);
    if (key != _shownKey) {
      // New request (first load, another date…): show what's saved for it.
      _shownKey = key;
      _set(showSaved ? Api.cached(fn, body) : null, null, false);
    } else if (data == null && error != null) {
      _set(null, null, false); // Retry: spinner instead of the old error
    }
    try {
      final fresh = await Api.fetch(fn, body);
      if (!mounted || seq != _seq) return;
      _set(fresh, null, false);
      onFresh(fresh);
    } on ApiError catch (e) {
      if (!mounted || seq != _seq) return;
      // Unpaired: the saved data belongs to a house this phone has left, so
      // say why instead of quietly showing it as "saved information".
      if (data == null || e.code == 'NOT_PAIRED') {
        _set(null, e.friendly, false);
      } else {
        _set(data, null, true);
      }
    }
  }

  void _set(Map<String, dynamic>? d, String? e, bool s) {
    if (!mounted) return;
    setState(() {
      data = d;
      error = e;
      stale = s;
    });
  }
}

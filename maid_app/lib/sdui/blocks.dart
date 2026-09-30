import 'package:flutter/material.dart';

import '../core/device.dart';
import '../core/i18n.dart';
import '../core/ota.dart';
import '../core/theme.dart';
import '../core/youtube.dart';
import '../widgets/common.dart';
import '../widgets/video.dart';
import 'actions.dart';

/// One block of a server-driven screen: {"type": "notice", ...its props}.
/// See docs/SDUI.md for every type and prop.
class UiBlock {
  UiBlock(this.type, this.props);
  final String type;
  final Map<String, dynamic> props;

  /// Reads a list leniently: anything that isn't {"type": "…"} is skipped.
  static List<UiBlock> list(Object? raw) => [
    if (raw is List)
      for (final b in raw)
        if (b is Map && b['type'] is String) UiBlock(b['type'] as String, Map<String, dynamic>.from(b)),
  ];

  /// Whether a block of [type] is in [blocks], or inside one of their children.
  static bool contains(List<UiBlock> blocks, String type) =>
      blocks.any((b) => b.type == type || contains(b.children, type));

  List<UiBlock> get children => list(props['children']);

  String? str(String k) => props[k] is String ? props[k] as String : null;
  double? number(String k) => props[k] is num ? (props[k] as num).toDouble() : null;
  bool flag(String k) => props[k] == true;

  /// Text in the chosen language, see [uiText].
  String? text(String k) => uiText(props[k]);

  /// A tap action the app can do, or null.
  String? get action => isUiAction(str('action')) ? str('action') : null;

  /// Shown at [now]? "hidden": true switches a block off. "from" / "until"
  /// are dates in India (YYYY-MM-DD, "until" includes that whole day) or
  /// exact times (2026-10-20T18:00:00+05:30).
  bool visibleAt(DateTime now) {
    if (flag('hidden')) return false;
    final today = ymd(now.toUtc().add(const Duration(hours: 5, minutes: 30)));
    final from = str('from'), until = str('until');
    if (from != null) {
      if (_date.hasMatch(from)) {
        if (today.compareTo(from) < 0) return false;
      } else if (DateTime.tryParse(from) case final t? when now.isBefore(t)) {
        return false;
      }
    }
    if (until != null) {
      if (_date.hasMatch(until)) {
        if (today.compareTo(until) > 0) return false;
      } else if (DateTime.tryParse(until) case final t? when !now.isBefore(t)) {
        return false;
      }
    }
    return true;
  }

  static final _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');
}

/// Text from a bundle, in the chosen language:
///   "Plain text"                       → as it is
///   {"en": "Hello", "kn": "ನಮಸ್ಕಾರ"}     → the chosen language, else English
///   {"key": "scan_qr"}                 → the app's own string (assets/i18n)
/// "{name}" becomes the cook's name. Null when there is no usable text.
String? uiText(Object? v) {
  String? s;
  if (v is String) {
    s = v;
  } else if (v is Map) {
    final key = v['key'];
    final own = v[L.code];
    s = key is String
        ? L.t(key)
        : own is String && own.trim().isNotEmpty
        ? own
        : v['en'] is String
        ? v['en'] as String
        : null;
  }
  s = s?.replaceAll('{name}', Device.name).trim();
  return s == null || s.isEmpty ? null : s;
}

/// Icons a bundle may name. (Icons have to be listed here: Flutter only
/// ships the icons the code uses.)
const uiIcons = <String, IconData>{
  'info': Icons.info_rounded,
  'campaign': Icons.campaign_rounded,
  'celebration': Icons.celebration_rounded,
  'gift': Icons.card_giftcard_rounded,
  'star': Icons.star_rounded,
  'favorite': Icons.favorite_rounded,
  'warning': Icons.warning_rounded,
  'check': Icons.check_circle_rounded,
  'cancel': Icons.cancel_rounded,
  'help': Icons.help_rounded,
  'event': Icons.event_rounded,
  'calendar': Icons.calendar_month_rounded,
  'schedule': Icons.schedule_rounded,
  'sun': Icons.wb_sunny_rounded,
  'moon': Icons.nights_stay_rounded,
  'restaurant': Icons.restaurant_menu_rounded,
  'people': Icons.groups_rounded,
  'wallet': Icons.account_balance_wallet_rounded,
  'payments': Icons.payments_rounded,
  'holiday': Icons.beach_access_rounded,
  'leave': Icons.event_busy_rounded,
  'history': Icons.history_rounded,
  'qr': Icons.qr_code_scanner_rounded,
  'phone': Icons.phone_rounded,
  'chat': Icons.chat_rounded,
  'video': Icons.smart_display_rounded,
  'link': Icons.open_in_new_rounded,
  'refresh': Icons.refresh_rounded,
  'location': Icons.location_on_rounded,
  'notifications': Icons.notifications_rounded,
  'home': Icons.home_rounded,
};

IconData? uiIcon(String? name) => uiIcons[name];

/// "tone" → colour (always shown with an icon and text, never colour alone).
Color uiTone(String? tone) => switch (tone) {
  'success' => StatusColors.done,
  'warning' => StatusColors.wait,
  'danger' => StatusColors.missed,
  'info' => StatusColors.holiday,
  'neutral' => StatusColors.grey,
  _ => accent,
};

typedef UiBuilder = Widget? Function(BuildContext context, UiBlock block);

/// Turns blocks into widgets. [screen] builds that screen's own blocks (the
/// salary card, Scan QR…); the general blocks (notice, text, button, image,
/// video, row, card, spacer, app_version) work on any screen.
///
/// Unknown types, blocks outside their dates, and blocks with missing or bad
/// values are left out, so a bundle written for a newer app, or with a typo,
/// never breaks this one.
class UiRenderer {
  const UiRenderer(this.screen);
  final Map<String, UiBuilder> screen;

  List<Widget> build(BuildContext context, List<UiBlock> blocks, {DateTime? now}) {
    final at = now ?? DateTime.now();
    return [
      for (final b in blocks)
        if (b.visibleAt(at)) ?_one(context, b, at),
    ];
  }

  Widget? _one(BuildContext context, UiBlock b, DateTime now) {
    try {
      final own = screen[b.type];
      if (own != null) return own(context, b);
      return switch (b.type) {
        'notice' => _notice(context, b),
        'text' => _text(b),
        'button' => _button(context, b),
        'image' => _image(context, b),
        'video' => _video(b),
        'spacer' => SizedBox(height: (b.number('height') ?? 8).clamp(0, 120).toDouble()),
        'row' => _row(context, b, now),
        'card' => _card(context, b, now),
        'app_version' => _version(),
        _ => null,
      };
    } catch (e) {
      debugPrint('SDUI: left out a "${b.type}" block: $e');
      return null;
    }
  }

  Widget? _notice(BuildContext context, UiBlock b) {
    final title = b.text('title'), text = b.text('text');
    if (title == null && text == null) return null;
    final color = uiTone(b.str('tone'));
    final action = b.action;
    return _Tappable(
      action: action,
      radius: 16,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(uiIcon(b.str('icon')) ?? Icons.campaign_rounded, color: color, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  if (text != null)
                    Text(
                      text,
                      style: TextStyle(fontSize: 16, fontWeight: title == null ? FontWeight.w600 : FontWeight.w500),
                    ),
                ],
              ),
            ),
            if (action != null) const Icon(Icons.chevron_right_rounded, color: StatusColors.grey),
          ],
        ),
      ),
    );
  }

  Widget? _text(UiBlock b) {
    final text = b.text('text');
    if (text == null) return null;
    return Text(
      text,
      textAlign: switch (b.str('align')) {
        'center' => TextAlign.center,
        'end' => TextAlign.end,
        _ => TextAlign.start,
      },
      style: TextStyle(
        fontSize: (b.number('size') ?? 17).clamp(13, 40).toDouble(),
        fontWeight: b.flag('bold') ? FontWeight.w800 : FontWeight.w500,
        color: b.flag('muted') ? espresso.withValues(alpha: 0.7) : null,
      ),
    );
  }

  Widget? _button(BuildContext context, UiBlock b) {
    final label = b.text('label'), action = b.action;
    if (label == null || action == null) return null;
    return BigButton(
      icon: uiIcon(b.str('icon')) ?? Icons.arrow_forward_rounded,
      label: label,
      filled: b.str('style') == 'filled',
      height: (b.number('height') ?? 64).clamp(56, 120).toDouble(),
      onPressed: () => runUiAction(context, action),
    );
  }

  Widget? _image(BuildContext context, UiBlock b) {
    final url = b.str('url');
    if (url == null || !url.startsWith('https://')) return null;
    final alt = b.text('alt');
    return _Tappable(
      action: b.action,
      radius: 18,
      label: alt,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.network(
          url,
          height: (b.number('height') ?? 170).clamp(60, 400).toDouble(),
          width: double.infinity,
          fit: BoxFit.cover,
          semanticLabel: alt,
          errorBuilder: (_, _, _) => const SizedBox.shrink(), // offline: just leave it out
        ),
      ),
    );
  }

  Widget? _video(UiBlock b) {
    final url = b.str('url');
    if (youtubeId(url) == null) return null;
    final title = b.text('title');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
        ],
        VideoThumb(url: url!, title: title ?? ''),
        TextButton.icon(
          onPressed: () => openInYoutube(url),
          icon: const Icon(Icons.open_in_new_rounded),
          label: Text(L.t('open_youtube'), style: const TextStyle(fontSize: 16)),
        ),
      ],
    );
  }

  /// Side by side; one under the other on a narrow phone (long Kannada labels).
  Widget? _row(BuildContext context, UiBlock b, DateTime now) {
    final kids = build(context, b.children, now: now);
    if (kids.length <= 1) return kids.firstOrNull;
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth < 360
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _gap(kids, const SizedBox(height: 12)))
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _gap([for (final k in kids) Expanded(child: k)], const SizedBox(width: 12)),
            ),
    );
  }

  Widget? _card(BuildContext context, UiBlock b, DateTime now) {
    final title = b.text('title');
    final kids = build(context, b.children, now: now);
    if (title == null && kids.isEmpty) return null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _gap([
            if (title != null)
              Row(
                children: [
                  Icon(uiIcon(b.str('icon')) ?? Icons.info_rounded, color: accent, size: 28),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ...kids,
          ], const SizedBox(height: 12)),
        ),
      ),
    );
  }

  /// Small line with the build and OTA patch, to check a phone got an update.
  Widget? _version() {
    final label = Ota.label;
    if (label.isEmpty) return null;
    return Text(
      '${L.t('app_title')} $label',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 13, color: espresso.withValues(alpha: 0.6)),
    );
  }

  static List<Widget> _gap(List<Widget> kids, Widget gap) => [
    for (var i = 0; i < kids.length; i++) ...[if (i > 0) gap, kids[i]],
  ];
}

/// [child] with an ink ripple when it has an action.
class _Tappable extends StatelessWidget {
  const _Tappable({required this.action, required this.radius, required this.child, this.decoration, this.label});
  final String? action;
  final double radius;
  final Widget child;
  final BoxDecoration? decoration;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final a = action;
    if (a == null) return decoration == null ? child : DecoratedBox(decoration: decoration!, child: child);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: () => runUiAction(context, a),
        child: Semantics(
          button: true,
          label: label,
          child: decoration == null ? child : Ink(decoration: decoration, child: child),
        ),
      ),
    );
  }
}

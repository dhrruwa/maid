final _re = RegExp(
  r'^(?:https?://)?(?:www\.|m\.|music\.)?(?:youtube\.com/(?:watch\?(?:.*&)?v=|shorts/|embed/|live/|v/)|youtu\.be/)([A-Za-z0-9_-]{11})',
);

/// The 11-character video id, or null if it is not a YouTube link.
String? youtubeId(String? url) {
  if (url == null) return null;
  return _re.firstMatch(url.trim())?.group(1);
}

String? youtubeThumb(String? url) {
  final id = youtubeId(url);
  return id == null ? null : 'https://img.youtube.com/vi/$id/hqdefault.jpg';
}

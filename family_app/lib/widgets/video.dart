import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../core/youtube.dart';

Future<void> openInYoutube(String url) =>
    launchUrl(Uri.parse(url.startsWith('http') ? url : 'https://$url'), mode: LaunchMode.externalApplication);

/// YouTube thumbnail with a play button. Tap → plays inside the app.
/// Give a [width] for a small thumbnail next to a dish name.
class VideoThumb extends StatelessWidget {
  const VideoThumb({super.key, required this.url, required this.title, this.width});
  final String url;
  final String title;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final thumb = youtubeThumb(url);
    if (thumb == null) return const SizedBox.shrink();
    final small = width != null && width! < 160;
    Widget body = ClipRRect(
      borderRadius: BorderRadius.circular(small ? 10 : 16),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(fit: StackFit.expand, children: [
          Image.network(
            thumb,
            fit: BoxFit.cover,
            cacheWidth: small ? 240 : 480, // keeps memory low on small phones
            errorBuilder: (_, _, _) => Container(
              color: Colors.black12,
              child: Icon(Icons.ondemand_video_rounded, size: small ? 24 : 48),
            ),
          ),
          Center(
            child: Container(
              padding: EdgeInsets.all(small ? 3 : 10),
              decoration: const BoxDecoration(color: Color(0xCCFF0000), shape: BoxShape.circle),
              child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: small ? 20 : 44),
            ),
          ),
        ]),
      ),
    );
    if (width != null) body = SizedBox(width: width, child: body);
    return Semantics(
      button: true,
      label: 'Play video: $title',
      child: GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VideoScreen(url: url, title: title))),
        child: body,
      ),
    );
  }
}

class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key, required this.url, required this.title});
  final String url;
  final String title;

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  late final YoutubePlayerController _c = YoutubePlayerController.fromVideoId(
    videoId: youtubeId(widget.url) ?? '',
    autoPlay: true,
  );

  @override
  void dispose() {
    _c.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(children: [
        YoutubePlayer(controller: _c),
        Padding(
          padding: const EdgeInsets.all(20),
          child: OutlinedButton.icon(
            onPressed: () => openInYoutube(widget.url),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Open in YouTube'),
          ),
        ),
      ]),
    );
  }
}

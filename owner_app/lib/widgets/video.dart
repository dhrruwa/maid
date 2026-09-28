import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../core/youtube.dart';

/// YouTube thumbnail with a play badge. Tap → in-app player.
class YoutubeThumb extends StatelessWidget {
  const YoutubeThumb({super.key, required this.url, this.height = 72, this.width = 128});
  final String url;
  final double height;
  final double width;

  @override
  Widget build(BuildContext context) {
    final thumb = youtubeThumb(url);
    if (thumb == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VideoScreen(url: url))),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(alignment: Alignment.center, children: [
          Image.network(
            thumb,
            width: width,
            height: height,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: width,
              height: height,
              color: Colors.black12,
              child: const Icon(Icons.ondemand_video_rounded),
            ),
          ),
          Container(
            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
            padding: const EdgeInsets.all(6),
            child: const Icon(Icons.play_arrow_rounded, color: Colors.white),
          ),
        ]),
      ),
    );
  }
}

Future<void> openInYoutube(String url) =>
    launchUrl(Uri.parse(url.startsWith('http') ? url : 'https://$url'), mode: LaunchMode.externalApplication);

class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key, required this.url, this.title});
  final String url;
  final String? title;

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
      appBar: AppBar(title: Text(widget.title ?? 'Recipe video')),
      body: ListView(children: [
        YoutubePlayer(controller: _c),
        Padding(
          padding: const EdgeInsets.all(16),
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

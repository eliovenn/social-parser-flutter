import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:social_parser/social_parser.dart';

class ResultView extends StatelessWidget {
  const ResultView({super.key, required this.result});
  final ParseResult result;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (result.title.isNotEmpty)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SelectableText(result.title,
                  style: Theme.of(context).textTheme.titleLarge)),
        if (result.sourceId != null)
          Text('源：${result.sourceId} · ${result.sourceVersion}',
              style: Theme.of(context).textTheme.bodySmall),
        if (result.content.isNotEmpty) SelectableText(result.content),
        const SizedBox(height: 12),
        LinkRow(label: '原帖链接', url: result.canonicalUrl.toString()),
        if (result.media.isEmpty)
          const Padding(
              padding: EdgeInsets.all(16), child: Text('这个帖子没有可显示的媒体。')),
        for (var i = 0; i < result.media.length; i++)
          MediaCard(item: result.media[i], index: i),
      ]);
}

class MediaCard extends StatelessWidget {
  const MediaCard({super.key, required this.item, required this.index});
  final MediaItem item;
  final int index;

  @override
  Widget build(BuildContext context) {
    final images =
        item.sources.where((s) => s.track == MediaTrack.image).toList();
    // Only image tracks are previewed. Videos, audio and manifests stay as links.
    final image = images.firstOrNull;
    final label = switch (item.type) {
      MediaType.image => '图片',
      MediaType.video => '视频',
      MediaType.audio => '音频',
      MediaType.animation => '动图',
      MediaType.livePhoto => 'Live Photo'
    };
    return Card(
        margin: const EdgeInsets.symmetric(vertical: 10),
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${index + 1}. $label',
                      style: Theme.of(context).textTheme.titleMedium),
                  if (image != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: ImagePreview(
                            key: ValueKey('image-$index-${image.url}'),
                            source: image)),
                  for (final s in item.sources) ...[
                    LinkRow(
                        label:
                            '${_trackName(s.track)}${s.kind == MediaSourceKind.direct ? '' : ' · ${s.kind.name.toUpperCase()}'}'
                            '${s.height == null ? '' : ' · ${s.height}p'}${s.extension == null ? '' : ' · ${s.extension}'}',
                        url: s.url.toString()),
                    if (s.headers.isNotEmpty)
                      ExpansionTile(
                        title: Text('访问需携带请求头：${s.headers.keys.join('、')}',
                            style: Theme.of(context).textTheme.bodySmall),
                        children: [
                          SelectableText(s.headers.entries
                              .map((e) => '${e.key}: ${e.value}')
                              .join('\n'))
                        ],
                      ),
                    const SizedBox(height: 8),
                  ],
                ])));
  }
}

String _trackName(MediaTrack track) => switch (track) {
      MediaTrack.image => '图片地址',
      MediaTrack.video => '视频轨道地址',
      MediaTrack.audio => '音频轨道地址',
      MediaTrack.audioVideo => '视频地址',
      MediaTrack.unknown => '媒体地址',
    };

class ImagePreview extends StatefulWidget {
  const ImagePreview({super.key, required this.source});
  final MediaSource source;
  @override
  State<ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<ImagePreview> {
  int _retry = 0;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 420),
      child: Image.network(widget.source.url.toString(),
          key: ValueKey(_retry),
          headers: widget.source.headers,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator())),
          errorBuilder: (context, error, stack) => SizedBox(
              height: 150,
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.broken_image_outlined),
                    const Text('图片预览失败，仍可复制下方地址'),
                    TextButton(
                        onPressed: () async {
                          await NetworkImage(widget.source.url.toString(),
                                  headers: widget.source.headers)
                              .evict();
                          if (mounted) setState(() => _retry++);
                        },
                        child: const Text('重试预览')),
                  ]))));
}

class LinkRow extends StatelessWidget {
  const LinkRow({super.key, required this.label, required this.url});
  final String label, url;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label)),
          IconButton(
              tooltip: '复制$label',
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: url));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('链接已复制'), duration: Duration(seconds: 1)));
                }
              })
        ]),
        SelectableText(url, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

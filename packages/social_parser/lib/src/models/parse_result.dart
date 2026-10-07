import 'media.dart';
import 'platform.dart';

class ParseResult {
  ParseResult({
    required this.platform,
    required this.inputUrl,
    required this.canonicalUrl,
    this.title = '',
    this.content = '',
    this.markdown,
    this.sourceId,
    this.sourceVersion,
    List<MediaItem> media = const [],
  }) : media = List.unmodifiable(media);
  final SocialPlatform platform;
  final String? sourceId, sourceVersion;
  final Uri inputUrl, canonicalUrl;
  final String title, content;
  final String? markdown;
  final List<MediaItem> media;

  ParseResult withUrls(Uri input, Uri canonical) => ParseResult(
        platform: platform,
        sourceId: sourceId,
        sourceVersion: sourceVersion,
        inputUrl: input,
        canonicalUrl: canonical,
        title: title,
        content: content,
        markdown: markdown,
        media: media,
      );

  /// This can contain signed media URLs/required headers. Store deliberately.
  Map<String, Object?> toJson() => {
        'platform': platform.name,
        'sourceId': sourceId,
        'sourceVersion': sourceVersion,
        'inputUrl': inputUrl.toString(),
        'canonicalUrl': canonicalUrl.toString(),
        'title': title,
        'content': content,
        'markdown': markdown,
        'media': media.map((m) => m.toJson()).toList(),
      };
  factory ParseResult.fromJson(Map<String, dynamic> json) => ParseResult(
        platform: SocialPlatform.fromId(json['platform'] as String),
        sourceId: json['sourceId'] as String?,
        sourceVersion: json['sourceVersion'] as String?,
        inputUrl: Uri.parse(json['inputUrl'] as String),
        canonicalUrl: Uri.parse(json['canonicalUrl'] as String),
        title: json['title'] as String? ?? '',
        content: json['content'] as String? ?? '',
        markdown: json['markdown'] as String?,
        media: (json['media'] as List)
            .map((m) => MediaItem.fromJson(Map<String, dynamic>.from(m as Map)))
            .toList(),
      );
}

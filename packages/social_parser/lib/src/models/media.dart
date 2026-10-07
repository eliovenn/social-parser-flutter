enum MediaType { image, video, audio, animation, livePhoto }

enum MediaSourceKind { direct, hls, dash }

enum MediaTrack { image, audio, video, audioVideo, unknown }

class MediaSource {
  MediaSource({
    required this.url,
    this.kind = MediaSourceKind.direct,
    this.track = MediaTrack.unknown,
    Map<String, String> headers = const {},
    this.formatId,
    this.extension,
    this.videoCodec,
    this.audioCodec,
    this.width,
    this.height,
    this.bitrate,
  }) : headers = Map.unmodifiable(headers);
  final Uri url;
  final MediaSourceKind kind;
  final MediaTrack track;
  final Map<String, String> headers;
  final String? formatId, extension, videoCodec, audioCodec;
  final int? width, height;
  final double? bitrate;

  Map<String, Object?> toJson() => {
        'url': url.toString(),
        'kind': kind.name,
        'track': track.name,
        'headers': headers,
        'formatId': formatId,
        'extension': extension,
        'videoCodec': videoCodec,
        'audioCodec': audioCodec,
        'width': width,
        'height': height,
        'bitrate': bitrate,
      };

  factory MediaSource.fromJson(Map<String, dynamic> json) => MediaSource(
        url: Uri.parse(json['url'] as String),
        kind: MediaSourceKind.values.byName(json['kind'] as String),
        track: MediaTrack.values.byName(json['track'] as String),
        headers: Map<String, String>.from(json['headers'] as Map? ?? {}),
        formatId: json['formatId'] as String?,
        extension: json['extension'] as String?,
        videoCodec: json['videoCodec'] as String?,
        audioCodec: json['audioCodec'] as String?,
        width: (json['width'] as num?)?.toInt(),
        height: (json['height'] as num?)?.toInt(),
        bitrate: (json['bitrate'] as num?)?.toDouble(),
      );
}

class MediaItem {
  MediaItem({
    required this.type,
    required List<MediaSource> sources,
    this.thumbnailUrl,
    this.width,
    this.height,
    this.duration,
  }) : sources = List.unmodifiable(sources);
  final MediaType type;

  /// Live Photos contain both image and video sources; video variants may
  /// contain separate audio/video tracks. No merging or downloading is done.
  final List<MediaSource> sources;
  final Uri? thumbnailUrl;
  final int? width, height;
  final Duration? duration;

  Map<String, Object?> toJson() => {
        'type': type.name,
        'sources': sources.map((s) => s.toJson()).toList(),
        'thumbnailUrl': thumbnailUrl?.toString(),
        'width': width,
        'height': height,
        'durationMs': duration?.inMilliseconds,
      };
  factory MediaItem.fromJson(Map<String, dynamic> json) => MediaItem(
        type: MediaType.values.byName(json['type'] as String),
        sources: (json['sources'] as List)
            .map((s) =>
                MediaSource.fromJson(Map<String, dynamic>.from(s as Map)))
            .toList(),
        thumbnailUrl: json['thumbnailUrl'] == null
            ? null
            : Uri.parse(json['thumbnailUrl'] as String),
        width: (json['width'] as num?)?.toInt(),
        height: (json['height'] as num?)?.toInt(),
        duration: json['durationMs'] == null
            ? null
            : Duration(milliseconds: (json['durationMs'] as num).toInt()),
      );
}

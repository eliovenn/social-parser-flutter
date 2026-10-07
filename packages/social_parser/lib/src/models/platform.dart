/// Extensible platform identity. Known constants remain source compatible.
class SocialPlatform {
  const SocialPlatform(this.name);
  final String name;
  static SocialPlatform fromId(String id) => SocialPlatform(id);
  static const bilibili = SocialPlatform('bilibili');
  static const coolapk = SocialPlatform('coolapk');
  static const douban = SocialPlatform('douban');
  static const douyin = SocialPlatform('douyin');
  static const tiktok = SocialPlatform('tiktok');
  static const facebook = SocialPlatform('facebook');
  static const instagram = SocialPlatform('instagram');
  static const kuaishou = SocialPlatform('kuaishou');
  static const pipix = SocialPlatform('pipix');
  static const threads = SocialPlatform('threads');
  static const tieba = SocialPlatform('tieba');
  static const twitter = SocialPlatform('twitter');
  static const weibo = SocialPlatform('weibo');
  static const weixin = SocialPlatform('weixin');
  static const xhs = SocialPlatform('xhs');
  static const xiaoheihe = SocialPlatform('xiaoheihe');
  static const youtube = SocialPlatform('youtube');
  static const zuiyou = SocialPlatform('zuiyou');
  static const snapchat = SocialPlatform('snapchat');
  static const zhihu = SocialPlatform('zhihu');
  static const values = [
    bilibili,
    coolapk,
    douban,
    douyin,
    tiktok,
    facebook,
    instagram,
    kuaishou,
    pipix,
    threads,
    tieba,
    twitter,
    weibo,
    weixin,
    xhs,
    xiaoheihe,
    youtube,
    zuiyou,
    snapchat,
    zhihu
  ];
  @override
  bool operator ==(Object other) =>
      other is SocialPlatform && other.name == name;
  @override
  int get hashCode => name.hashCode;
  @override
  String toString() => name;
}

class PlatformCapability {
  const PlatformCapability({
    required this.platform,
    required this.name,
    required this.mediaTypes,
    this.supportsJavaScript = false,
    this.available = true,
    this.javaScriptAvailable = false,
  });
  final SocialPlatform platform;
  final String name;
  final List<String> mediaTypes;
  final bool supportsJavaScript;
  final bool available;
  final bool javaScriptAvailable;
}

import '../errors/parse_exception.dart';

bool hostMatches(Uri url, String domain) =>
    url.host == domain || url.host.endsWith('.$domain');

Uri extractUrl(String text) {
  final value = text.trim();
  final match =
      RegExp(r'https?://[^\s<>"「」【】]+', caseSensitive: false).firstMatch(value);
  var raw = match?.group(0) ?? value;
  raw = raw.replaceFirst(RegExp(r'[，。！？、；：）)\]}>]+$'), '');
  if (!raw.contains('://')) raw = 'https://$raw';
  final url = Uri.tryParse(raw);
  if (url == null ||
      !['http', 'https'].contains(url.scheme) ||
      url.host.isEmpty ||
      !url.host.contains('.') ||
      url.userInfo.isNotEmpty ||
      raw.contains(RegExp(r'\s'))) {
    throw const ParseException(
        ParseErrorCode.invalidInput, 'Enter a supported URL or share text');
  }
  return url;
}

Uri cleanUrl(Uri url, Set<String> keep) => url.replace(
      queryParameters: {
        for (final e in url.queryParametersAll.entries)
          if (keep.contains(e.key)) e.key: e.value,
      },
      fragment: '',
    );

import 'dart:convert';

Map<String, String> parseCookieInput(String input) {
  var text = input.trim();
  if (text.isEmpty) return {};
  if (text.toLowerCase().startsWith('cookie:')) text = text.substring(7).trim();
  final result = <String, String>{};
  if (text.startsWith('{')) {
    try {
      final data = jsonDecode(text);
      if (data is! Map || data.values.any((v) => v is! String)) {
        throw const FormatException();
      }
      result.addAll(Map<String, String>.from(data));
    } catch (_) {
      throw const FormatException('Cookie JSON 格式不正确，请使用字符串键值对象。');
    }
  } else {
    for (final part in text.split(';')) {
      if (part.trim().isEmpty) continue;
      final eq = part.indexOf('=');
      if (eq < 1) {
        throw const FormatException(
            'Cookie 格式不正确，请使用 name=value; name2=value2。');
      }
      result[part.substring(0, eq).trim()] = part.substring(eq + 1).trim();
    }
  }
  for (final entry in result.entries) {
    if (!RegExp(r'^[!#$%&\x27*+\-.^_`|~0-9a-zA-Z]+$').hasMatch(entry.key) ||
        RegExp(r'[\r\n;\x00-\x1f\x7f]').hasMatch(entry.value)) {
      throw const FormatException('Cookie 含无效名称或控制字符，请重新复制请求中的 Cookie。');
    }
  }
  return result;
}

Map<String, String> cookiesForPlatform(
  String input,
  String? platformId, {
  required Iterable<String> platformIds,
}) {
  if (input.trim().isEmpty) return {};
  try {
    final data = jsonDecode(input);
    if (data is! Map<String, dynamic>) throw const FormatException();
    final cookies = <String, Map<String, String>>{};
    for (final entry in data.entries) {
      if (!platformIds.contains(entry.key)) {
        throw const FormatException('Cookie 对象包含未知平台，请使用平台列表中的标识。');
      }
      final value = entry.value;
      if (value is! String && value is! Map<String, dynamic>) {
        throw const FormatException();
      }
      cookies[entry.key] = parseCookieInput(
        value is String ? value : jsonEncode(value),
      );
    }
    return cookies[platformId] ?? {};
  } on FormatException {
    throw const FormatException(
      'Cookie 请填写平台对象，例如 {"xhs":"a=1; b=2","douyin":{"sessionid":"值"}}；平台标识和 Cookie 值需有效。',
    );
  }
}

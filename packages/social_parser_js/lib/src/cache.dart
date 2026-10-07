import 'dart:convert';

/// Bounded process memory cache; source revisions receive separate namespaces.
class SourceCache {
  final _entries = <String, ({String value, DateTime expires})>{};
  int _bytes = 0;
  Object? get(String namespace, String key) {
    final id = '$namespace:$key', value = _entries.remove('$namespace:$key');
    if (value == null) return null;
    if (DateTime.now().isAfter(value.expires)) {
      _bytes -= utf8.encode(value.value).length;
      return null;
    }
    _entries[id] = value;
    return jsonDecode(value.value);
  }

  void set(String namespace, String key, Object? value, int ttlMs) {
    if (key.length > 4096 || ttlMs < 1 || ttlMs > 3600000) {
      throw const FormatException('Invalid cache entry');
    }
    final text = jsonEncode(value), length = utf8.encode(text).length;
    if (length > 2 * 1024 * 1024) {
      throw const FormatException('Cache entry exceeds 2 MiB');
    }
    final id = '$namespace:$key', previous = _entries.remove('$namespace:$key');
    if (previous != null) _bytes -= utf8.encode(previous.value).length;
    while (_entries.isNotEmpty &&
        (_bytes + length > 8 * 1024 * 1024 || _entries.length >= 32)) {
      _bytes -= utf8.encode(_entries.remove(_entries.keys.first)!.value).length;
    }
    _entries[id] = (
      value: text,
      expires: DateTime.now().add(Duration(milliseconds: ttlMs)),
    );
    _bytes += length;
  }
}

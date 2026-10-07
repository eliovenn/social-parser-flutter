import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../errors/parse_exception.dart';
import '../network/http_client.dart';
import '../options/parse_options.dart';
import 'runtime.dart';
import 'source.dart';

class InstalledSource {
  const InstalledSource(this.current,
      {this.previous, this.enabled = true, this.indexUrl, this.builtin});
  final SourceFile current;
  final SourceFile? previous, builtin;
  final bool enabled;
  final Uri? indexUrl;
  InstalledSource copy(
          {SourceFile? current,
          SourceFile? previous,
          bool? enabled,
          Uri? indexUrl}) =>
      InstalledSource(current ?? this.current,
          previous: previous ?? this.previous,
          builtin: builtin,
          enabled: enabled ?? this.enabled,
          indexUrl: indexUrl ?? this.indexUrl);
}

class SourceUpdate {
  const SourceUpdate(this.id, this.version, this.url, this.sha256);
  final String id, version, sha256;
  final Uri url;
}

/// App-owned source storage. Only code/metadata/preferences are persisted.
/// Transactions publish in-memory state only after the atomic disk replacement.
class SourceManager {
  SourceManager(
      {required this.runtime,
      this.directory,
      ParserHttpClient? http,
      this.allowLocalhostHttp = false,
      this.builtinsOnly = false})
      : http = http ?? DioParserHttpClient();
  final SourceRuntime runtime;
  final Directory? directory;
  final ParserHttpClient http;
  final bool allowLocalhostHttp;
  final bool builtinsOnly;
  Map<String, InstalledSource> _sources = {};
  Map<String, String> _defaults = {};
  List<InstalledSource> get installed => List.unmodifiable(_sources.values);
  String? defaultFor(String platformId) => _defaults[platformId];
  Future<void> initialize(Iterable<SourceFile> builtins) async {
    _sources = {
      for (final f in builtins) f.manifest.id: InstalledSource(f, builtin: f)
    };
    _defaults = {};
    final dir = directory;
    if (dir == null) return;
    await dir.create(recursive: true);
    final file = File('${dir.path}/sources.json');
    if (!await file.exists()) return;
    try {
      if (await file.length() > 64 * 1024 * 1024) return;
      final data = jsonDecode(await file.readAsString()) as Map;
      for (final value in data['sources'] as List) {
        try {
          final current = SourceFile.parse(value['code'] as String);
          final old = _sources[current.manifest.id];
          if (builtinsOnly && old == null) continue;
          if (old != null &&
              _compare(current.manifest.version, old.current.manifest.version) <
                  0) {
            continue;
          }
          await runtime.validate(current);
          final previous = value['previous'] == null
              ? null
              : SourceFile.parse(value['previous'] as String);
          if (old != null &&
              old.current.manifest.platformId != current.manifest.platformId) {
            continue;
          }
          if (previous != null &&
              (previous.manifest.id != current.manifest.id ||
                  previous.manifest.platformId !=
                      current.manifest.platformId)) {
            continue;
          }
          final index = value['indexUrl'] == null
              ? null
              : Uri.parse(value['indexUrl'] as String);
          if (index != null) _checkDownload(index);
          _sources[current.manifest.id] = InstalledSource(current,
              previous: previous,
              enabled: value['enabled'] as bool,
              builtin: old?.builtin,
              indexUrl: index);
        } catch (_) {/* A corrupt record cannot replace a bundled source. */}
      }
      final defaults = Map<String, String>.from(data['defaults'] as Map? ?? {});
      _defaults = {
        for (final e in defaults.entries)
          if (_sources[e.value]?.current.manifest.platformId == e.key)
            e.key: e.value
      };
    } catch (_) {/* Retain valid records and bundled sources. */}
  }

  SourceFile? find(Uri url, {String? sourceId}) {
    final candidates = _sources.values
        .where((s) => s.enabled && s.current.manifest.matches(url));
    if (sourceId != null) {
      return candidates
          .where((s) => s.current.manifest.id == sourceId)
          .firstOrNull
          ?.current;
    }
    return candidates
            .where((s) =>
                _defaults[s.current.manifest.platformId] ==
                s.current.manifest.id)
            .firstOrNull
            ?.current ??
        candidates.where((s) => s.builtin != null).firstOrNull?.current ??
        candidates.firstOrNull?.current;
  }

  String normalizeInput(String input) {
    for (final s in installed.where((s) => s.enabled)) {
      final value = s.current.manifest.normalizeInput(input);
      if (value != input) return value;
    }
    return input;
  }

  Future<void> importFile(File file) async {
    if (await file.length() > 8 * 1024 * 1024) {
      throw const ParseException(
          ParseErrorCode.invalidSource, 'Source exceeds 8 MiB');
    }
    await importCode(await file.readAsString());
  }

  Future<void> importCode(String code, {Uri? indexUrl}) async {
    if (indexUrl != null) _checkDownload(indexUrl);
    final file = SourceFile.parse(code);
    await runtime.validate(file);
    await _commit((sources, defaults) {
      _replace(sources, file, indexUrl);
    });
  }

  void _replace(
      Map<String, InstalledSource> sources, SourceFile file, Uri? index) {
    final old = sources[file.manifest.id];
    if (builtinsOnly && old?.builtin == null) {
      throw const ParseException(ParseErrorCode.invalidSource,
          'Only bundled platforms may be updated');
    }
    if (old != null &&
        old.current.manifest.platformId != file.manifest.platformId) {
      throw const ParseException(
          ParseErrorCode.invalidSource, 'Source platform identity changed');
    }
    sources[file.manifest.id] = InstalledSource(file,
        previous: old?.current,
        builtin: old?.builtin,
        enabled: old?.enabled ?? true,
        indexUrl: index ?? old?.indexUrl);
  }

  void _checkDownload(Uri url) {
    if (url.scheme == 'https' && url.host.isNotEmpty && url.userInfo.isEmpty) {
      return;
    }
    if (allowLocalhostHttp &&
        url.scheme == 'http' &&
        url.userInfo.isEmpty &&
        ['localhost', '127.0.0.1', '::1'].contains(url.host)) {
      return;
    }
    throw const ParseException(
        ParseErrorCode.invalidSource, 'Source downloads require HTTPS');
  }

  Future<String> _download(Uri uri) async {
    for (var i = 0; i < 9; i++) {
      _checkDownload(uri);
      final r = await http.get(uri, ParseOptions(followRedirects: false));
      _checkDownload(r.uri);
      if ([301, 302, 303, 307, 308].contains(r.statusCode)) {
        final location = r.headers.entries
            .where((e) => e.key.toLowerCase() == 'location')
            .expand((e) => e.value)
            .firstOrNull;
        if (location == null) break;
        uri = r.uri.resolve(location);
        continue;
      }
      if (r.statusCode < 200 || r.statusCode >= 300) {
        throw const ParseException(
            ParseErrorCode.network, 'Source server returned an error');
      }
      if (utf8.encode(r.body).length > 8 * 1024 * 1024) {
        throw const ParseException(
            ParseErrorCode.invalidSource, 'Downloaded source is too large');
      }
      return r.body;
    }
    throw const ParseException(
        ParseErrorCode.network, 'Source redirect failed');
  }

  Future<List<SourceUpdate>> catalog(Uri indexUrl) async {
    try {
      final data = jsonDecode(await _download(indexUrl)) as Map;
      if (data['apiVersion'] != 1) {
        throw const ParseException(
            ParseErrorCode.incompatibleSource, 'Unsupported source index');
      }
      final entries = <SourceUpdate>[], ids = <String>{};
      for (final e in data['sources'] as List) {
        final entry = SourceUpdate(e['id'] as String, e['version'] as String,
            indexUrl.resolve(e['url'] as String), e['sha256'] as String);
        if (!ids.add(entry.id) ||
            !RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,99}$').hasMatch(entry.id) ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.sha256)) {
          throw const FormatException();
        }
        _compare(entry.version, '0.0.0');
        _checkDownload(entry.url);
        entries.add(entry);
      }
      return entries;
    } on ParseException {
      rethrow;
    } catch (_) {
      throw const ParseException(
          ParseErrorCode.invalidSource, 'Invalid source index');
    }
  }

  Future<void> install(Uri indexUrl, {required String sourceId}) async {
    final entry =
        (await catalog(indexUrl)).where((s) => s.id == sourceId).firstOrNull;
    if (entry == null) {
      throw const ParseException(
          ParseErrorCode.invalidSource, 'Source is absent from index');
    }
    await _apply(entry, indexUrl);
  }

  Future<List<SourceUpdate>> checkUpdates() async {
    final result = <SourceUpdate>[], catalogs = <Uri, List<SourceUpdate>>{};
    for (final s in installed) {
      final index = s.indexUrl;
      if (index == null) continue;
      final entries = catalogs[index] ??= await catalog(index);
      for (final e in entries.where((e) => e.id == s.current.manifest.id)) {
        if (_compare(e.version, s.current.manifest.version) > 0) result.add(e);
      }
    }
    return result;
  }

  int _compare(String a, String b) {
    if (!RegExp(r'^\d{1,9}\.\d{1,9}\.\d{1,9}$').hasMatch(a)) {
      throw const ParseException(
          ParseErrorCode.invalidSource, 'Invalid source version');
    }
    final x = a.split('.').map(int.parse).toList(),
        y = b.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      if (x[i] != y[i]) return x[i].compareTo(y[i]);
    }
    return 0;
  }

  Future<void> update(String id) async {
    final s = _require(_sources, id), index = s.indexUrl;
    if (index == null) {
      throw const ParseException(
          ParseErrorCode.invalidSource, 'No update index configured');
    }
    final e = (await catalog(index)).where((e) => e.id == id).firstOrNull;
    if (e != null && _compare(e.version, s.current.manifest.version) > 0) {
      await _apply(e, index, onlyNewer: true);
    }
  }

  Future<void> _apply(SourceUpdate entry, Uri index,
      {bool onlyNewer = false}) async {
    final code = await _download(entry.url);
    if (sha256.convert(utf8.encode(code)).toString() != entry.sha256) {
      throw const ParseException(
          ParseErrorCode.integrityFailure, 'Source checksum mismatch');
    }
    final source = SourceFile.parse(code);
    if (source.manifest.id != entry.id ||
        source.manifest.version != entry.version) {
      throw const ParseException(
          ParseErrorCode.invalidSource, 'Source differs from its index entry');
    }
    await runtime.validate(source);
    await _commit((sources, defaults) {
      if (onlyNewer) {
        final old = _require(sources, entry.id);
        if (old.indexUrl != index ||
            _compare(entry.version, old.current.manifest.version) <= 0) {
          return;
        }
      }
      _replace(sources, source, index);
    });
  }

  InstalledSource _require(Map<String, InstalledSource> sources, String id) =>
      sources[id] ??
      (throw const ParseException(
          ParseErrorCode.invalidSource, 'Source is not installed'));
  Future<void> setUpdateIndex(String id, Uri index) async {
    _checkDownload(index);
    await _commit((s, d) {
      s[id] = _require(s, id).copy(indexUrl: index);
    });
  }

  /// Assign the official catalog to bundled platforms in one storage transaction.
  Future<void> setBuiltinUpdateIndex(Uri index) async {
    _checkDownload(index);
    await _commit((sources, defaults) {
      for (final entry in sources.entries.toList()) {
        if (entry.value.builtin != null) {
          sources[entry.key] = entry.value.copy(indexUrl: index);
        }
      }
    });
  }

  /// Checks once per catalog, installs newer bundled platforms independently.
  /// Catalog errors are thrown; individual download/validation errors are returned.
  Future<Map<String, Object?>> updateBuiltins() async {
    final updates = await checkUpdates();
    final results = <String, Object?>{};
    for (final update in updates) {
      final installed = _sources[update.id];
      if (installed?.builtin == null || installed?.indexUrl == null) continue;
      try {
        await _apply(update, installed!.indexUrl!, onlyNewer: true);
        results[update.id] = null;
      } catch (error) {
        results[update.id] = error;
      }
    }
    return results;
  }

  Future<void> setEnabled(String id, bool enabled) => _commit((s, d) {
        s[id] = _require(s, id).copy(enabled: enabled);
      });
  Future<void> setDefault(String id) => _commit((s, d) {
        final source = _require(s, id);
        d[source.current.manifest.platformId] = id;
      });
  Future<void> rollback(String id) => _commit((s, d) {
        final v = _require(s, id), target = v.previous ?? v.builtin;
        if (target != null) {
          s[id] = v.copy(current: target, previous: v.current);
        }
      });
  Future<void> remove(String id) => _commit((s, d) {
        final v = _require(s, id);
        if (v.builtin == null) {
          s.remove(id);
        } else {
          s[id] =
              InstalledSource(v.builtin!, builtin: v.builtin, enabled: false);
        }
        d.removeWhere((_, v) => v == id);
      });
  Future<void> _write = Future.value();
  Future<void> _commit(
      void Function(Map<String, InstalledSource>, Map<String, String>) change) {
    final task = _write.then((_) async {
      final sources = Map.of(_sources), defaults = Map.of(_defaults);
      change(sources, defaults);
      final dir = directory;
      if (dir != null) {
        final state = jsonEncode({
          'sources': [
            for (final s in sources.values)
              {
                'code': s.current.code,
                'previous': s.previous?.code,
                'enabled': s.enabled,
                'indexUrl': s.indexUrl?.toString()
              }
          ],
          'defaults': defaults
        });
        if (utf8.encode(state).length > 64 * 1024 * 1024) {
          throw const ParseException(
              ParseErrorCode.invalidSource, 'Source store exceeds 64 MiB');
        }
        final temp = File('${dir.path}/sources.tmp');
        await temp.writeAsString(state, flush: true);
        await temp.rename('${dir.path}/sources.json');
      }
      _sources = sources;
      _defaults = defaults;
    });
    _write = task.catchError((Object _) {});
    return task;
  }
}

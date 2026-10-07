class ParseOptions {
  ParseOptions({
    Map<String, String> cookies = const {},
    Map<String, String> headers = const {},
    this.timeout = const Duration(seconds: 45),
    this.proxy,
    this.followRedirects = true,
    this.cancellation,
  })  : cookies = Map.unmodifiable(cookies),
        headers = Map.unmodifiable(headers) {
    if (timeout <= Duration.zero) throw ArgumentError.value(timeout, 'timeout');
    if (proxy != null &&
        (proxy!.scheme != 'http' ||
            proxy!.host.isEmpty ||
            proxy!.userInfo.isNotEmpty)) {
      throw ArgumentError(
          'proxy must be an HTTP proxy URI without credentials');
    }
  }
  final Map<String, String> cookies, headers;
  final Duration timeout;

  /// False returns 3xx responses for platform-specific redirect handling.
  final bool followRedirects;
  final ParseCancellation? cancellation;

  /// HTTP CONNECT proxy. SOCKS and proxy authentication are not yet supported.
  final Uri? proxy;
}

class ParseCancellation {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  final List<void Function()> _callbacks = [];
  void add(void Function() callback) {
    if (_cancelled) {
      callback();
    } else {
      _callbacks.add(callback);
    }
  }

  void remove(void Function() callback) => _callbacks.remove(callback);
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final c in List.of(_callbacks)) {
      c();
    }
    _callbacks.clear();
  }
}

import '../network/http_client.dart';
import '../options/parse_options.dart';
import 'source.dart';

abstract interface class SourceRuntime {
  Future<void> validate(SourceFile source);
  Future<Map<String, dynamic>> execute(SourceFile source, String operation,
      Map<String, dynamic> input, ParserHttpClient http, ParseOptions options);
}

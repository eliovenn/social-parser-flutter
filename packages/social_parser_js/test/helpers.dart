import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_parser/social_parser.dart';
import 'package:social_parser_js/social_parser_js.dart';

final runtime = FjsSourceRuntime();
final manager = SourceManager(runtime: runtime);
void setupSources() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await manager.initialize(
      Directory('packages/social_parser_js/assets/sources')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.js'))
          .map((f) => SourceFile.parse(f.readAsStringSync())),
    );
  });
}

SocialParser testParser({ParserHttpClient? http}) =>
    SocialParser(sourceRuntime: runtime, sources: manager, http: http);

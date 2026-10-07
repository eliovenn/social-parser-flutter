import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:social_parser/social_parser.dart';
import 'package:social_parser_js/social_parser_js.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const link = String.fromEnvironment('YOUTUBE_TEST_LINK');
  testWidgets('YouTube with JS sources and embedded QuickJS', (tester) async {
    final result = await (await createSocialParser()).parse(link,
        options: ParseOptions(timeout: const Duration(seconds: 120)));
    expect(result.platform, SocialPlatform.youtube);
    expect(result.media, isNotEmpty);
    expect(result.media.expand((m) => m.sources), isNotEmpty);
    // Zero can mean this video did not require a challenge; native EJS fixture
    // tests independently verify both signature and n transformations.
    print('YouTube device: ${result.title}; ${result.media.length} media; '
        '${result.media.expand((m) => m.sources).length} sources');
  }, skip: link.isEmpty, timeout: const Timeout(Duration(minutes: 3)));
}

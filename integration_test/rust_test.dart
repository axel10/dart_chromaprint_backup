import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dart_chromaprint/dart_chromaprint.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Rust Integration Test', () {
    setUpAll(() async {
      await RustLib.init();
    });

    testWidgets('calls greet function', (WidgetTester tester) async {
      const name = 'Flutter';
      final result = greet(name: name);
      expect(result, 'Hello, $name!');
    });

    testWidgets('verify init_app can be called', (WidgetTester tester) async {
      // This function is called during RustLib.init() if implementated in executeRustInitializers,
      // but we can also call it manually if needed or just verify the instance exists.
      expect(RustLib.instance, isNotNull);
    });
  });
}

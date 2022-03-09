import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamome_flutter/kamome_flutter.dart';

void main() {
  const MethodChannel channel = MethodChannel('kamome_flutter');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });
}

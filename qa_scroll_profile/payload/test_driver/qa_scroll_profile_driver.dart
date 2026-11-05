// QA host driver: the app reports actual engine FrameTiming values.
import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() async {
  await integrationDriver(responseDataCallback: (data) async {
    if (data == null || data['scroll_profile'] == null) {
      throw StateError('Missing actual Android profile report');
    }
    final target = Platform.environment['QA_RAW_PATH'];
    if (target == null) throw StateError('QA_RAW_PATH required');
    await File(target).writeAsString(jsonEncode(data['scroll_profile']));
  });
}

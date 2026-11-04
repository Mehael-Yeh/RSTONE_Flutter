import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/services/obsidian_data_service.dart';

void main() {
  test(
      'new consumer declares 2.0.2 in default, executable fallback and pubspec',
      () {
    expect(ObsidianDataService().appVersion, '2.0.2');
    expect(File('lib/main.dart').readAsStringSync(),
        contains("defaultValue: '2.0.2'"));
    final match =
        RegExp(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$', multiLine: true)
            .firstMatch(File('pubspec.yaml').readAsStringSync())!;
    expect(match[1], '2.0.2');
    // Never emit the full build code in assertions or logs.
    expect(
        int.parse(match[2]!) > 0 && int.parse(match[2]!) <= 2100000000, isTrue);
  });
}

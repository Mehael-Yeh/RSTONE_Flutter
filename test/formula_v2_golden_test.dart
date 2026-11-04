import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/utils/formula_protocol_codec.dart';

void main() {
  final data =
      jsonDecode(File('test/fixtures/golden_v2.json').readAsStringSync())
          as Map;
  for (final c in data['cases'] as List) {
    test('frozen v2 ${c['name']}', () {
      final raw = base64Decode(c['rawBase64'] as String);
      if (c['accept'] != true) {
        expect(() => FormulaProtocolCodec.decode(raw), throwsFormatException);
        return;
      }
      final d = FormulaProtocolCodec.decode(raw);
      expect(d.toJson(), c['model']);
      expect(FormulaProtocolCodec.encode(d), raw);
      final parts = FormulaProtocolCodec.ingredientParts(
          d.rows.first.first, d.associatedProducts);
      final actual = <Map<String, String>>[];
      for (final p in parts) {
        final kind = p.target == null ? 'text' : 'link';
        if (kind == 'text' &&
            actual.isNotEmpty &&
            actual.last['kind'] == 'text') {
          actual.last['text'] = '${actual.last['text']}${p.text}';
        } else {
          actual.add({'kind': kind, 'text': p.text,
            if (p.target != null) 'displayText': '[[产品列表/${p.target}]]'});
        }
      }
      expect(actual, c['expectedFirstCellSegments']);
    });
  }
}

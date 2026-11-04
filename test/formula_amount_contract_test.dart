import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/formula_document.dart';
import 'package:rst_flutter/utils/formula_protocol_codec.dart';
import 'package:rst_flutter/data_sync/services/index_manager.dart';

Map<String, dynamic> specimen() => jsonDecode(
        File('test/fixtures/recipe_protocol/valid.model.json').readAsStringSync())
    as Map<String, dynamic>;
String document(Map<String, dynamic> m) =>
    utf8.decode(FormulaProtocolCodec.encode(FormulaDocument.fromJson(m)));
Map<String, String> files(Map<String, dynamic> m) => {
      '产品列表/RS87654321-Q5.md': 'product',
      '产品配方/${m['title']}.md': document(m),
    };
void main() {
  for (final bad in ['-1', '10-2', '任意垃圾量', '-10--1', '1.5.5']) {
    test('main recipe rejects invalid non-owner amount $bad', () {
      final m = specimen()..['rows'][2][1] = bad;
      expect(() => parseOfficialFiles(files(m)), throwsFormatException);
    });
    test('example recipe still rejects invalid amount $bad', () {
      final m = specimen()
        ..['classification'] = 'example'
        ..['rows'][2][1] = bad;
      expect(() => parseOfficialFiles(files(m)), throwsFormatException);
    });
  }
  for (final role in ['example', 'reference', 'unverified']) {
    test('$role without a positive owner stays readable but earns no credit', () {
      final m = specimen()
        ..['classification'] = role
        ..['rows'][0][1] = '0';
      final parsed = parseOfficialFiles(files(m));
      expect(parsed.formulas, hasLength(1));
      expect(parsed.formulas.single.formulaDocument!.classification, role);
    });
  }
  test('main without a positive owner remains rejected', () {
    final m = specimen()..['rows'][0][1] = '0';
    expect(() => parseOfficialFiles(files(m)), throwsFormatException);
  });
  test('closed unknown and range amounts stay accepted', () {
    final m = specimen();
    m['rows'] = [
      ['[[RS87654321-Q5]]', '40', '', '', ''],
      ['水', '10-12', '', '', ''],
      ['固化剂', '按NCO/OH=1.1另加', '', '', ''],
      ['助剂', '适量', '', '', ''],
      ['溶剂', '0', '', '', ''],
    ];
    expect(parseOfficialFiles(files(m)).formulas, hasLength(1));
  });
  test('an inverted NCO/OH ratio inside the unknown form is rejected', () {
    final m = specimen()..['rows'][2][1] = '适量（NCO/OH=1.2-1.1）';
    expect(() => parseOfficialFiles(files(m)), throwsFormatException);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/formula_document.dart';
import 'package:rst_flutter/utils/formula_protocol_codec.dart';
import 'formula_structured_test.dart' show specimen;

void main() {
  test('associated paths cannot inject the fixed display folder', () {
    for (final target in ['产品列表/RS87654321-Q5', '../RS87654321-Q5', 'other/RS87654321-Q5']) {
      final m = specimen()..['schema'] = 'rstone-recipe/2';
      m['associatedProducts'] = ['RS87654321-Q5', target];
      m['rows'][0][0] = '[[$target]]';
      final d = FormulaDocument.fromJson(m);
      expect(FormulaProtocolCodec.ingredientParts(d.rows.first.first, d.associatedProducts).single.target, isNull);
      expect(FormulaProtocolCodec.body(d), isNot(contains('[[')));
      expect(FormulaProtocolCodec.body(d), contains(FormulaProtocolCodec.entityText('[[$target]]')));
    }
  });
  test('revision002 body qualifies valid token without changing model', () {
    final m = specimen()..['schema'] = 'rstone-recipe/2';
    m['rows'][0][0] = '[[RS87654321-Q5]]';
    final d = FormulaDocument.fromJson(m);
    expect(FormulaProtocolCodec.body(d), contains('[[产品列表/RS87654321-Q5]]'));
    expect(d.toJson(), m);
    expect(FormulaProtocolCodec.ingredientParts(d.rows.first.first, d.associatedProducts).single,
        (text: '[[RS87654321-Q5]]', target: 'RS87654321-Q5'));
  });
}

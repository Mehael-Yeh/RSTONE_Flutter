import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/utils/formula_table_clipboard_parser.dart';

void main() {
  const header = '原料编号\t投入数(g)\t百分比(%)\t供应商\t备注\n';
  test(
      'clipboard preserves exact five strings, zero/range/unknown/empty tail and quoted multiline pipe',
      () {
    final dynamic result = FormulaTableClipboardParser.parse(
        '$header[[RS1|树脂]]\t0\t\t\t\nwater\t10-12\t\t\t" line1\nline2|x "\ncuring\t按NCO/OH=1.1另加\t\t A \t');
    expect(result.isValid, isTrue);
    expect(result.rows, [
      ['[[RS1|树脂]]', '0', '', '', ''],
      ['water', '10-12', '', '', ' line1\nline2|x '],
      ['curing', '按NCO/OH=1.1另加', '', ' A ', '']
    ]);
    final dynamic again =
        FormulaTableClipboardParser.parse(result.tsv as String);
    expect(again.rows, result.rows);
  });
  test(
      'clipboard rejects six columns and missing cells instead of truncating/padding',
      () {
    for (final row in [
      'water\t1\t100%\tSupplier\textra\tsixth',
      'water\t1\t\t'
    ]) {
      expect(FormulaTableClipboardParser.parse('$header$row').isValid, isFalse);
    }
  });
  test('Markdown wiki aliases and escaped pipes are not cell delimiters', () {
    final dynamic r = FormulaTableClipboardParser.parse(
        '| 原料编号 | 投入数(g) | 百分比(%) | 供应商 | 备注 |\n| --- | --- | --- | --- | --- |\n| [[RS1|树脂]] | 适量 | | | a\\|b |');
    expect(r.isValid, isTrue);
    expect(r.rows, [
      ['[[RS1|树脂]]', '适量', '', '', 'a|b']
    ]);
  });
}

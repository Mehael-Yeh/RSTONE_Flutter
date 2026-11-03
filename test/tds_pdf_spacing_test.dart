import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/services/tds_pdf_service.dart';

void main() {
  const cases = {
    'CJK captures': ['1. 合 成样品保持原字。', '1. 合成样品保持原字。'],
    'CJK punctuation captures': [
      '温度稳定 。数值保留 12.5 mPa·s',
      '温度稳定。数值保留 12.5 mPa·s'
    ],
    'ASCII punctuation capture': ['中文 , ASCII 42±2%', '中文, ASCII 42±2%'],
    'opening bracket capture': ['（ 合成）[ sample]', '（合成）[sample]'],
    'wrapped ASCII words': ['  alpha\t beta\r\ngamma  ', 'alpha beta gamma'],
    'technical values': ['3. 数值 7.25 与 20–40 不改', '3. 数值 7.25 与 20–40 不改'],
    'literal dollar text': [r'字面标记 $1 与 $1$2 原样保留。', r'字面标记 $1 与 $1$2 原样保留。'],
  };
  for (final entry in cases.entries) {
    test('paragraph spacing preserves ${entry.key}', () {
      expect(
        TdsPdfService.normalizeParagraphSpacingForTesting(entry.value[0]),
        entry.value[1],
      );
    });
  }
}

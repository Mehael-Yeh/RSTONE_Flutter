import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/services/tds_pdf_service.dart';

void main() {
  test('a document without a resin type does not use disclaimer as subtitle',
      () {
    const markdown = '''
# RS-DEMO-001

## 产品介绍
这是合成测试正文，不是产品类型副标题。

## 物理性能
| 项目 | 数值 |
| --- | --- |
| 固体含量 | 42±2% |

## 免责声明
嘉兴锐石化工有限公司在本技术数据表中的说明仅供参考。
''';

    expect(TdsPdfService.parseProductSubtitleForTesting(markdown), isNull);
  });

  test('a genuine resin subtitle is retained with a Markdown disclaimer', () {
    const markdown = '''
---
title: synthetic
---
# RS-DEMO-002

水性聚氨酯

## 产品介绍
合成正文中提及产品技术数据表，不是页眉。

## 免责声明
此合成免责声明不应替代树脂类型。
''';

    expect(TdsPdfService.parseProductSubtitleForTesting(markdown), '水性聚氨酯');
    expect(
      TdsPdfService.parseProductSubtitleForTesting(
          markdown.replaceAll('\n', '\r\n')),
      '水性聚氨酯',
    );
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/services/obsidian_data_service.dart';
import 'package:rst_flutter/services/tds_pdf_service.dart';
import 'package:rst_flutter/utils/formula_table_clipboard_parser.dart';
import 'package:rst_flutter/utils/natural_sort.dart';
import 'package:rst_flutter/widgets/product_detail/formula_content_parser.dart';

void main() {
  group('ProductItem.fromMdContent', () {
    test('parses product fields and list-style tags', () {
      const content = '''
---
tags:
  - 水性
  - UV
工程师: 王工
实验牌号: exp-01
固含: 45
---
正文
''';

      final item = ProductItem.fromMdContent('assets/产品列表/RS1001.md', content);

      expect(item.folder, '产品列表');
      expect(item.fileName, 'RS1001');
      expect(item.tags, ['水性', 'UV']);
      expect(item.engineer, '王工');
      expect(item.experimentalCode, 'exp-01');
      expect(item.solidContent, '45');
    });

    test('detects formula folder and uses fallback table fields', () {
      const content = '''
| 栏1 | 栏2 |
|---|---|
| A | B |
''';

      final item = ProductItem.fromMdContent('assets/产品配方/RS1001-银.md', content);

      expect(item.folder, '产品配方');
      expect(item.getTableFields(), {'名称': 'RS1001-银'});
    });

    test('does not parse frontmatter delimiter as tag', () {
      const content = '''
---
tags:
  - 水性
  - PU
  - 底漆
  - 耐汽油
  - 中漆
---
[[RD1160-黑]]
''';

      final item = ProductItem.fromMdContent('assets/产品列表/RD1160.md', content);

      expect(item.tags, ['水性', 'PU', '底漆', '耐汽油', '中漆']);
    });

    test('parses wiki-style links in application fields as plain text', () {
      const content = '''
---
tags:
  - PC
  - ABS
底漆: "[[RS8214-黑]]"
中漆: "[[RD1160-黑]]"
面漆: "[[RD1010-4-亮]]"
基材:
---
''';

      final item = ProductItem.fromMdContent('assets/产品应用/PC-ABS.md', content);

      expect(item.tags, ['PC', 'ABS']);
      expect(item.primer, 'RS8214-黑');
      expect(item.midCoat, 'RD1160-黑');
      expect(item.topCoat, 'RD1010-4-亮');
      expect(item.baseMaterial, '');
    });

    test('collects wiki references from markdown body for searching', () {
      const content = '''
---
tags:
  - 水性
---
[[RS8214-银]] [[RS8214-黑]]
''';

      final item = ProductItem.fromMdContent('assets/产品应用/水性PU2涂哑光-1.md', content);

      expect(item.linkedWikiReferences, ['RS8214-银', 'RS8214-黑']);
      expect(item.searchText, contains('rs8214-黑'.toLowerCase()));
    });
  });

  group('ObsidianDataService.search', () {
    test('keeps PU and UV curing-mode tags mutually exclusive except dual cure', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final service = ObsidianDataService();

      await service.initialize();

      bool hasTag(ProductItem item, String tag) =>
          item.tags.any((candidate) => candidate.toLowerCase() == tag);
      bool hasDualCureTag(ProductItem item) => item.tags.contains('双固化');

      final uvResults = service.search('UV');
      expect(uvResults, isNotEmpty);
      expect(
        uvResults.where((item) => hasTag(item, 'pu') && !hasDualCureTag(item)),
        isEmpty,
      );

      final puResults = service.search('PU');
      expect(puResults, isNotEmpty);
      expect(
        puResults.where((item) => hasTag(item, 'uv') && !hasDualCureTag(item)),
        isEmpty,
      );
    });
  });

  group('FormulaTableClipboardParser', () {
    test('accepts standard Markdown formula tables', () {
      const clipboard = '''
| 原料编号 | 投入数（g) | 百分比(%) | 供应商 | 备注 |
|----------|------------|-----------|--------|------|
| RS7930 | 75.00 | 75.000% | 锐石 | |
| TPO | 1.00 | 1.000% | 巴斯夫 | 三者预溶 |
''';

      final result = FormulaTableClipboardParser.parse(clipboard);

      expect(result.isValid, isTrue);
      expect(result.markdown, contains('| 原料编号 | 投入数（g) | 百分比(%) | 供应商 | 备注 |'));
      expect(result.markdown, contains('| TPO | 1.00 | 1.000% | 巴斯夫 | 三者预溶 |'));
    });

    test('converts Excel copied tab-separated formula tables to Markdown', () {
      const clipboard = '原料编号\t投入数（g)\t百分比(%)\t供应商\n'
          'RD919-23\t70.00 \t0.78 \t锐石 \n'
          'TEGO 810\t0.10 \t0.00 \t德固赛 \n';

      final result = FormulaTableClipboardParser.parse(clipboard);

      expect(result.isValid, isTrue);
      expect(result.markdown, '''
| 原料编号 | 投入数（g) | 百分比(%) | 供应商 |
| --- | --- | --- | --- |
| RD919-23 | 70.00 | 0.78 | 锐石 |
| TEGO 810 | 0.10 | 0.00 | 德固赛 |'''.trim());
    });

    test('rejects tables without required formula headers', () {
      const clipboard = '''
名称	供应商
RS7930	锐石
''';

      final result = FormulaTableClipboardParser.parse(clipboard);

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('表头无效'));
    });
  });

  group('FormulaContentParser', () {
    test('ignores standalone multi wiki-link lines after frontmatter', () {
      const content = '''
---
工程师: 孙燕娜
---
[[RS8214-银]] [[RS8214-黑]]
''';

      final parsed = FormulaContentParser.parse(content);

      expect(parsed.preTableContent, isEmpty);
      expect(parsed.postTableContent, isEmpty);
    });
  });

  group('TdsPdfService', () {
    test('groups punctuation with the previous render chunk', () {
      const text = '正文，包含括号（内容）、引号“内容”，以及 punctuation.';

      final chunks =
          TdsPdfService.splitTextIntoNoLeadingPunctuationChunks(text);

      expect(chunks, contains('文，'));
      expect(chunks, contains('容）'));
      expect(chunks, contains('容”'));
      expect(chunks, contains('punctuation.'));
      expect(chunks.join(), text);
    });

    test('keeps leading punctuation as its own first render chunk', () {
      const text = '，开头标点保持原样';

      final chunks =
          TdsPdfService.splitTextIntoNoLeadingPunctuationChunks(text);

      expect(chunks.first, '，');
      expect(chunks.join(), text);
    });
  });

  group('compareNaturalText', () {
    test('sorts product codes by numeric value and digit-run length', () {
      final codes = [
        'RD1010-4',
        'RD1011-6',
        'RD824-8',
        'RD1011-5',
        'RD02',
        'RD2',
      ];

      codes.sort(compareNaturalText);

      expect(codes, [
        'RD2',
        'RD02',
        'RD824-8',
        'RD1010-4',
        'RD1011-5',
        'RD1011-6',
      ]);
    });
  });
}

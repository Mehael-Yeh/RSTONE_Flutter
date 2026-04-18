import 'package:flutter_test/flutter_test.dart';

import 'package:rst_flutter/models/product_item.dart';
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
}

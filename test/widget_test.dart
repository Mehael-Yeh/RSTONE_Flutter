import 'package:flutter_test/flutter_test.dart';

import 'package:rst_flutter/models/product_item.dart';

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
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/product_item.dart';

const _frontmatter = '''
---
tags:
  - 水性
产品状态: 停用
---
''';

void main() {
  group('ProductItem lifecycle status', () {
    test('parses 停用 as discontinued', () {
      final item = ProductItem.fromMdContent('产品列表/RS91001.md', _frontmatter);

      expect(item.productStatus, '停用');
      expect(item.isDiscontinued, isTrue);
    });

    test('treats 停止, 禁用 and 废止 as discontinued', () {
      for (final status in ['停止', '禁用', '废止']) {
        final item = ProductItem.fromMdContent(
            '产品列表/RS91001.md', '---\n产品状态: $status\n---\n');
        expect(item.isDiscontinued, isTrue, reason: status);
      }
    });

    test('shows status without striking 不推广 and other review states', () {
      for (final status in ['不推广', '已转产', '内部使用', '资料牌号冲突']) {
        final item = ProductItem.fromMdContent(
            '产品列表/RS91001.md', '---\n产品状态: $status\n---\n');
        expect(item.productStatus, status, reason: status);
        expect(item.isDiscontinued, isFalse, reason: status);
      }
    });

    test('missing or blank status stays active', () {
      final missing =
          ProductItem.fromMdContent('产品列表/RS91001.md', '---\ntags: []\n---\n');
      final blank =
          ProductItem.fromMdContent('产品列表/RS91001.md', '---\n产品状态:\n---\n');

      expect(missing.productStatus, isNull);
      expect(missing.isDiscontinued, isFalse);
      expect(blank.productStatus, isNull);
      expect(blank.isDiscontinued, isFalse);
    });

    test('body-only strikethrough text does not mark the grade discontinued',
        () {
      final item = ProductItem.fromMdContent(
          '产品列表/RS91001.md', '---\ntags:\n  - 水性\n---\n# ~~RS91001~~\n');

      expect(item.productStatus, isNull);
      expect(item.isDiscontinued, isFalse);
    });
  });
}

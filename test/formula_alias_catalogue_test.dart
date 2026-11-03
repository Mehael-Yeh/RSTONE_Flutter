import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/utils/formula_association.dart';

ProductItem _product(String id, {String? experimental}) =>
    ProductItem.fromMdContent('产品列表/$id.md',
        experimental == null ? '' : '---\n实验牌号: "$experimental"\n---\n');
ProductItem _formula(String name, String content) =>
    ProductItem.fromMdContent('产品配方/$name.md', content);

void main() {
  final old = _product('RS990101-8B.2', experimental: 'RD990201-8B.2');
  final canonical = _product('rd990201-8b.2');
  final catalogue = [old, canonical];
  final participation = {
    'metadata': _formula('synthetic-declared',
        '---\n关联产品: "[[产品列表/RD990201-8B.2.md|resin]]"\n---\n'),
    'material': _formula('synthetic-material',
        '| 原料编号 | 用量 |\n| --- | --- |\n| [[RD990201-8B.2]] | 1 |\n'),
    'legacy title': _formula('RD990201-8B.2-亮', ''),
  };
  for (final entry in participation.entries) {
    test('${entry.key} cannot be stolen from a canonical product', () {
      expect(
          linkedFormulasForProduct(old, [entry.value],
              productCatalog: catalogue),
          isEmpty);
      expect(
          linkedFormulasForProduct(canonical, [entry.value],
              productCatalog: catalogue),
          [entry.value]);
    });
  }

  test('historical alias remains when no independent full-grade product exists',
      () {
    for (final recipe in participation.values) {
      expect(linkedFormulasForProduct(old, [recipe], productCatalog: [old]),
          [recipe]);
    }
  });

  test(
      'base and sibling suffixes do not suppress a distinct full experimental alias',
      () {
    final others = ['RD990201', 'RD990201-8B', 'RD990201-8B.3', 'RD990201-8.2']
        .map(_product)
        .toList();
    expect(
        linkedFormulasForProduct(old, [participation['metadata']!],
            productCatalog: [old, ...others]),
        [participation['metadata']!]);
  });

  test('non-product folders cannot reserve a product canonical identity', () {
    final otherFolder = ProductItem.fromMdContent('产品应用/RD990201-8B.2.md', '');
    expect(
        linkedFormulasForProduct(old, [participation['material']!],
            productCatalog: [old, otherFolder]),
        [participation['material']!]);
  });

  test('explicit formal participation still joins a multi-resin union once',
      () {
    final third = _product('RS990301-2B');
    final recipe = _formula('synthetic-blend', '''
---
关联产品: "[[RD990201-8B.2]] [[RS990101-8B.2]]"
---
| 原料编号 | 用量 |
| --- | --- |
| [[RS990301-2B]] | 1 |
| [[RD990201-8B.2]] | 1 |
''');
    for (final product in [old, canonical, third]) {
      expect(
          linkedFormulasForProduct(product, [recipe, recipe],
              productCatalog: [...catalogue, third]),
          [recipe]);
    }
  });

  test('no inferred mapping to an unrelated formal full grade', () {
    final unrelated = _product('RS990201-8B.2');
    expect(
        linkedFormulasForProduct(unrelated, [participation['metadata']!],
            productCatalog: [...catalogue, unrelated]),
        isEmpty);
  });

  test(
      'catalogue changes recompute ownership rather than retaining a stale alias',
      () {
    final recipe = participation['metadata']!;
    expect(linkedFormulasForProduct(old, [recipe], productCatalog: [old]),
        [recipe]);
    expect(linkedFormulasForProduct(old, [recipe], productCatalog: catalogue),
        isEmpty);
    expect(linkedFormulasForProduct(old, [recipe], productCatalog: [old]),
        [recipe]);
  });

  test('self experimental identity does not hide the canonical full grade', () {
    final self = _product('RD990201-8B.2', experimental: 'RD990201-8B.2');
    final recipe = participation['metadata']!;
    expect(linkedFormulasForProduct(self, [recipe], productCatalog: [self]),
        [recipe]);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/utils/formula_association.dart' as association;

ProductItem _product(String grade, {String content = ''}) =>
    ProductItem.fromMdContent('产品列表/$grade.md', content);

ProductItem _formula(String name, String content) =>
    ProductItem.fromMdContent('产品配方/$name.md', content);

// Replay every original expectation against the indexed path as well.
List<ProductItem> linkedFormulasForProduct(
    ProductItem product, Iterable<ProductItem> formulas) {
  final indexed = association.FormulaAssociationIndex(
          productCatalog: [product], formulas: formulas)
      .forProduct(product);
  expect(
      indexed,
      association.linkedFormulasForProduct(product, formulas,
          productCatalog: [product]));
  return indexed;
}

void main() {
  test('ingredient wikilinks associate every blend component', () {
    final blend = _formula('RS901001-亮', '''
| 原料编号 | 投入数(g) | 备注 |
| --- | --- | --- |
| [[RS901001]] | 60 | |
| [[RS901002-2B]] | 40 | |
''');

    expect(linkedFormulasForProduct(_product('RS901001'), [blend]), [blend]);
    expect(linkedFormulasForProduct(_product('RS901002-2B'), [blend]), [blend]);
  });

  test('scalar association metadata supports a multi-product arbitrary title',
      () {
    final blend = _formula('水性混拼方案-01', '''
---
关联产品: '[[RS901001]] [[RS901002-2B]]'
---
> 施工比例按原文保留。
''');

    expect(linkedFormulasForProduct(_product('RS901001'), [blend]), [blend]);
    expect(linkedFormulasForProduct(_product('RS901002-2B'), [blend]), [blend]);
  });

  test(
      'wiki display aliases use the exact product target in tables and metadata',
      () {
    final blend = _formula('带显示别名的混拼', r'''
---
关联产品: '[[产品列表/RD900910-22.md|旧实验牌号]]'
---
| 序号 | 原料编号 | 投入数(g) |
| --- | --- | --- |
| 1 | [[产品列表/RS901002-2B.md\|副树脂]] | 40 |
''');

    expect(
      linkedFormulasForProduct(
        _product('RS907965', content: '---\n实验牌号: RD900910-22\n---\n'),
        [blend],
      ),
      [blend],
    );
    expect(linkedFormulasForProduct(_product('RS901002-2B'), [blend]), [blend]);
    expect(linkedFormulasForProduct(_product('RS901002'), [blend]), isEmpty);
  });

  test('fenced examples are not ingredient participation', () {
    final example = _formula('施工说明', '''
```markdown
| 原料编号 | 投入数(g) |
| --- | --- |
| [[RS901001]] | 100 |
```
''');

    expect(linkedFormulasForProduct(_product('RS901001'), [example]), isEmpty);
  });

  test('explicit participation wins over a stale legacy filename', () {
    final formula = _formula('RS901001-亮', '''
---
关联产品: '[[RS901002-2B]]'
---
''');

    expect(linkedFormulasForProduct(_product('RS901001'), [formula]), isEmpty);
    expect(
        linkedFormulasForProduct(_product('RS901002-2B'), [formula]), [formula]);
  });

  for (final header in ['原料名称', '原料', '组分']) {
    test('recognizes explicit product links under the $header material header',
        () {
      final formula = _formula('混拼示例', '''
| $header | 用量 |
| --- | --- |
| [[RS901002-2B]] | 40 |
''');

      expect(linkedFormulasForProduct(_product('RS901002-2B'), [formula]),
          [formula]);
    });
  }

  test(
      'a material mention without a Markdown table delimiter is not a recipe row',
      () {
    final note = _formula('说明文字', '''
| 原料编号 | 对比对象 |
| [[RS901001]] | 仅举例，不是配方 |
''');

    expect(linkedFormulasForProduct(_product('RS901001'), [note]), isEmpty);
  });

  group('retained identity and safety invariants', () {
    for (final finish in ['亮', '哑', '银', '黑', '底']) {
      test('legacy $finish title retains the complete letter suffix', () {
        final formula = _formula('RS901170-8B-$finish', '');
        expect(linkedFormulasForProduct(_product('rs901170-8b'), [formula]),
            [formula]);
        for (final other in ['RS901170', 'RS901170-8', 'RS901170-2B', 'RD901170-8B']) {
          expect(linkedFormulasForProduct(_product(other), [formula]), isEmpty);
        }
      });
    }

    test('only the explicitly declared full experimental grade is an alias',
        () {
      final formula = _formula('实验混拼', '''
---
关联产品: '[[RD901170-8B]]'
---
''');
      expect(
          linkedFormulasForProduct(
              _product('RS901170-8B',
                  content: '---\n实验牌号: "[[RD901170-8B]]"\n---\n'),
              [formula]),
          [formula]);
      for (final experimental in [
        'RD901170',
        'RD901170-8',
        'RD901170-2B',
        '1170-8B'
      ]) {
        expect(
            linkedFormulasForProduct(
                _product('RS901170-8B',
                    content: '---\n实验牌号: $experimental\n---\n'),
                [formula]),
            isEmpty);
      }
      expect(
          linkedFormulasForProduct(_product('RS901170-8B'), [formula]), isEmpty);
    });

    const mentions = {
      'plain prose': '此处提及 [[RS901001]]，不是参与原料。',
      'standalone navigation': '[[RS901001]]',
      'construction note': '> 施工对照：[[RS901001]]',
      'another metadata field': '---\n备注: "[[RS901001]]"\n---\n',
      'note column': '| 原料编号 | 备注 |\n| --- | --- |\n| 水 | 对照 [[RS901001]] |',
      'unrelated table': '| 对比产品 | 说明 |\n| --- | --- |\n| [[RS901001]] | 非原料 |',
      'numeric link': '| 原料编号 | 用量 |\n| --- | --- |\n| [[1001]] | 100 |',
      'unconfirmed RD identity':
          '| 原料编号 | 用量 |\n| --- | --- |\n| [[RD901001]] | 100 |',
      'metadata object array': '---\n关联产品: [{牌号: RS901001}]\n---\n',
      'invalid YAML': '---\n关联产品: ["[[RS901001]]"\n---\n',
    };
    for (final entry in mentions.entries) {
      test('${entry.key} does not declare participation', () {
        expect(
            linkedFormulasForProduct(
                _product('RS901001'), [_formula('说明', entry.value)]),
            isEmpty);
      });
    }

    test('metadata and material references are unioned once per formula name',
        () {
      final formula = _formula('混拼方案', '''
---
关联产品: '[[RS901001]] [[RS901001]]'
---
| 原料编号 | 用量 |
| --- | --- |
| [[RS901001]] | 60 |
| [[RS901002-2B]] | 40 |
''');
      for (final grade in ['RS901001', 'RS901002-2B']) {
        expect(linkedFormulasForProduct(_product(grade), [formula, formula]),
            [formula]);
      }
    });

    test('CRLF metadata retains exact association', () {
      final formula =
          _formula('CRLF混拼', '---\r\n关联产品: "[[RS901001]]"\r\n---\r\n');
      expect(
          linkedFormulasForProduct(_product('RS901001'), [formula]), [formula]);
    });

    test('non-product query and non-formula candidate are not associated', () {
      expect(linkedFormulasForProduct(_formula('RS901001', ''), []), isEmpty);
      expect(
          linkedFormulasForProduct(_product('RS901001'), [_product('RS901001-亮')]),
          isEmpty);
    });
  });
}

import 'dart:math';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/models/formula_document.dart';
import 'package:rst_flutter/utils/formula_association.dart';
import 'package:rst_flutter/utils/formula_protocol_codec.dart';
import 'product_scroll_regression_test.dart' as fixture;
import 'support/sync_fixture.dart';

ProductItem p(String name, {String? alias}) => ProductItem.fromMdContent(
    '产品列表/$name.md', alias == null ? '' : '---\n实验牌号: $alias\n---\n');
ProductItem f(String name, String content) =>
    ProductItem.fromMdContent('产品配方/$name.md', content);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('one index per revision survives freshly allocated list getters', () {
    final ds = fixture.Catalog();
    final ps = fixture.products(244);
    ds.setItemsForTesting(products: ps);
    ds.recipes = fixture.CountingList(fixture.formulas(244, ps));
    final first = ds.formulaAssociations;
    expect(ds.recipes.reads, 244);
    for (var i = 0; i < 20; i++) {
      expect(ds.formulaAssociations, same(first));
    }
    expect(ds.recipes.reads, 244);
    expect(() => first.forProduct(ps.first).clear(), throwsUnsupportedError);
    ds.recipes = fixture.CountingList(fixture.formulas(244, [ps.last]));
    ds.revision++;
    final next = ds.formulaAssociations;
    expect(next, isNot(same(first)));
    expect(ds.recipes.reads, 244);
    expect(next.forProduct(ps.first), isEmpty);
    expect(next.forProduct(ps.last), hasLength(244));
    expect(first.forProduct(ps.first), hasLength(1));
    expect(ds.formulaAssociations, same(next));
    expect(ds.recipes.reads, 244);
    ds.dispose();
  });
  test(
      'same-size identity replacement and deletion rebuild canonical ownership',
      () {
    final old = p('RS900001', alias: 'RD900001-2B');
    final canonical = p('RD900001-2B');
    final recipe = f('SYNTHETIC', '---\n关联产品: "[[RD900001-2B]]"\n---\n');
    final ds = fixture.Catalog();
    ds.setItemsForTesting(products: [old, p('RS900002')]);
    ds.recipes = fixture.CountingList([recipe]);
    expect(ds.formulaAssociations.forProduct(old), [recipe]);
    ds.setItemsForTesting(products: [old, canonical]);
    ds.revision++;
    expect(ds.formulaAssociations.forProduct(old), isEmpty);
    expect(ds.formulaAssociations.forProduct(canonical), [recipe]);
    ds.setItemsForTesting(products: [old]);
    ds.revision++;
    expect(ds.formulaAssociations.forProduct(old), [recipe]);
    final replaced = p('RS900001', alias: 'RD900099-2B');
    ds.setItemsForTesting(products: [replaced]);
    ds.revision++;
    expect(ds.formulaAssociations.forProduct(replaced), isEmpty);
    ds.recipes = fixture.CountingList([]);
    ds.revision++;
    expect(ds.formulaAssociations.forProduct(replaced), isEmpty);
    ds.dispose();
  });
  for (final schema in [
    'legacy',
    FormulaDocument.schema,
    FormulaDocument.schemaV2
  ]) {
    for (final n in [244, 500]) {
      test(
          '$schema $n fixed-seed indexed associations equal old query sets and order',
          () {
        final random = Random(900204);
        final ps = fixture.products(n);
        final recipes = <ProductItem>[];
        for (var i = 0; i < n; i++) {
          final refs = {
            ps[random.nextInt(n)].fileName,
            ps[random.nextInt(n)].fileName
          }.toList();
          if (schema == 'legacy') {
            recipes.add(f('SYNTHETIC-$i',
                '---\n关联产品: "${refs.map((r) => '[[$r]]').join(' ')}"\n---\n'));
          } else {
            final doc = fixture
                .formulas(1, [ps.first])
                .single
                .formulaDocument!
                .toJson();
            doc['schema'] = schema;
            doc['recipeId'] = 'SYNTHETIC-$i';
            doc['ownerProduct'] = refs.first;
            doc['associatedProducts'] = refs;
            recipes.add(ProductItem.fromMdContent(
                '产品配方/SYNTHETIC-$i.md',
                utf8.decode(FormulaProtocolCodec.encode(
                    FormulaDocument.fromJson(doc)))));
          }
        }
        recipes
            .add(recipes.first); // repeated filename retains first occurrence
        final index =
            FormulaAssociationIndex(productCatalog: ps, formulas: recipes);
        for (final product in ps) {
          expect(index.forProduct(product),
              linkedFormulasForProduct(product, recipes, productCatalog: ps));
        }
      });
    }
  }
  test(
      'real signed snapshot, overlay, import/reload and deletion invalidate index',
      () async {
    final signed = SignedFixture();
    await signed.initialize();
    final store = await signed.memoryStorage();
    final app = await signed.app(store);
    try {
      final official = {
        '产品列表/RS900001.md': '---\n实验牌号: RD900001\n---\n',
        '产品配方/SYNTHETIC.md': '---\n关联产品: "[[RD900001]]"\n---\n'
      };
      await signed.publish(1, official);
      expect(await app.sync!.synchronize(), isTrue);
      void check(int count) {
        final product =
            app.products.singleWhere((p) => p.fileName == 'RS900001');
        expect(app.formulaAssociations.forProduct(product), hasLength(count));
        expect(
            app.formulaAssociations.forProduct(product),
            linkedFormulasForProduct(product, app.formulas,
                productCatalog: app.products));
      }

      check(1);
      final first = app.formulaAssociations;
      app.clearLogs();
      expect(app.formulaAssociations, same(first));
      await app.addProductMarkdown(
          code: 'RS900001', markdown: '---\n实验牌号: RD900099\n---\n');
      check(0);
      expect(app.formulaAssociations, isNot(same(first)));
      await app.deleteManualItem(app.products.single);
      check(1);
      await store.writeText(
          'user/产品列表/RS900001.md', '---\n实验牌号: RD900099\n---\n');
      await app.reloadUserItems();
      check(0);
      await app.clearAllManualMarkdownData();
      check(1);
      await signed.publish(2, {
        ...official,
        '产品配方/SYNTHETIC.md': '---\n关联产品: "[[RS900001]]"\n---\n'
      });
      expect(await app.sync!.synchronize(), isTrue);
      check(1);
      await signed
          .publish(3, {'产品列表/RS900001.md': official['产品列表/RS900001.md']!});
      expect(await app.sync!.synchronize(), isTrue);
      check(0);
    } finally {
      app.dispose();
      await store.close();
    }
  });
}

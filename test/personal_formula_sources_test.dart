import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/models/formula_document.dart';
import 'package:rst_flutter/utils/formula_association.dart';
import 'support/sync_fixture.dart';
import 'personal_edit_transaction_test.dart' show InterruptedStorage;

FormulaDocument recipe(String name, String grade) => FormulaDocument.fromJson({
      'schema': 'rstone-recipe/1',
      'recipeId': 'personal-$name',
      'title': name,
      'classification': 'unverified',
      'ownerProduct': grade,
      'associatedProducts': [grade],
      'columns': ['原料编号', '投入数(g)', '百分比(%)', '供应商', '备注'],
      'rows': [
        ['water', '10', '', '', '']
      ],
      'preTable': [],
      'content': [],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'binding proof mismatch fails closed; explicit clear removes reference metadata',
      () async {
    final f = SignedFixture();
    await f.initialize();
    final s = await f.memoryStorage();
    final a = await f.app(s);
    await f.publish(1, {'产品列表/RD900605.md': product('official')});
    await a.sync!.synchronize();
    await a.addFormulaDocument(recipe('proof', 'RD900605'));
    await s.writeText('user/record-links/产品配方/proof.md.json',
        '{"version":1,"sha256":"wrong","records":{}}');
    await a.reloadUserItems();
    expect(a.formulaAssociations.forProduct(a.products.single), isEmpty);
    expect(a.formulas, hasLength(1));
    await a.clearAllManualMarkdownData();
    expect(await s.keys('user/record-links/'), isEmpty);
  });
  test('failed recipe markdown write preserves old document and its binding',
      () async {
    final f = SignedFixture();
    await f.initialize();
    final base = await f.memoryStorage();
    final s = InterruptedStorage(base);
    final a = await f.app(s);
    await f.publish(1, {'产品列表/RD900606.md': product('official')});
    await a.sync!.synchronize();
    await a.addFormulaDocument(recipe('proof', 'RD900606'));
    final original = await base.readText('user/产品配方/proof.md');
    final binding = await base.readText('user/record-links/产品配方/proof.md.json');
    s.failWriteKey = 'user/产品配方/proof.md';
    await expectLater(
        a.addFormulaDocument(recipe('proof', 'RD900606')), throwsStateError);
    expect(await base.readText('user/产品配方/proof.md'), original);
    expect(
        await base.readText('user/record-links/产品配方/proof.md.json'), binding);
    await a.reloadUserItems();
    expect(a.formulaAssociations.forProduct(a.products.single), hasLength(1));
  });
  test(
      'personal reference to official record does not transfer to later personal overlay',
      () async {
    final f = SignedFixture();
    await f.initialize();
    final s = await f.memoryStorage();
    final a = await f.app(s);
    await f.publish(1, {'产品列表/RD900604.md': product('official')});
    await a.sync!.synchronize();
    await a.addFormulaDocument(recipe('official-ref', 'RD900604'));
    expect(a.formulaAssociations.forProduct(a.products.single), hasLength(1));
    await a.addProductMarkdown(code: 'RD900604', markdown: product('personal'));
    expect(a.formulaAssociations.forProduct(a.products.single), isEmpty);
    await a.reloadUserItems();
    expect(a.formulaAssociations.forProduct(a.products.single), isEmpty);
    await a.deleteManualItem(a.products.single);
    expect(a.formulaAssociations.forProduct(a.products.single), hasLength(1));
  });
  test(
      'legitimate personal recipe links own target and official target; revision cache and reload agree',
      () async {
    final f = SignedFixture();
    await f.initialize();
    final s = await f.memoryStorage();
    final a = await f.app(s);
    await f.publish(1, {
      '产品列表/RD900601.md': product('official'),
      '产品列表/RD900602.md': product('official')
    });
    await a.sync!.synchronize();
    await a.addProductMarkdown(code: 'RD900601', markdown: product('personal'));
    await a.addFormulaDocument(recipe('own', 'RD900601'));
    await a.addFormulaDocument(recipe('official-target', 'RD900602'));
    final index = a.formulaAssociations;
    expect(identical(index, a.formulaAssociations), isTrue);
    for (final p in a.products) {
      final indexed = index.forProduct(p);
      expect(indexed, hasLength(1));
      expect(
          linkedFormulasForProduct(p, a.formulas, productCatalog: a.products),
          indexed);
      expect(indexed.single.origin, DataOrigin.user);
    }
    await a.reloadUserItems();
    expect(identical(index, a.formulaAssociations), isFalse);
    expect(a.products.map((p) => a.formulaAssociations.forProduct(p).length),
        [1, 1]);
  });
  test(
      'origin and concrete user record paths both gate cached and direct matching',
      () {
    final p = ProductItem.fromMdContent('user/产品列表/RD900603.md', '',
        origin: DataOrigin.user);
    for (final legacy in [false, true]) {
      const raw = '---\n关联产品: "[[RD900603]]"\n---\n';
      ProductItem formula(DataOrigin origin, String path) => legacy
          ? ProductItem.fromMdContent(path, raw, origin: origin)
          : ProductItem(
              fileName: 'recipe',
              filePath: path,
              folder: '产品配方',
              rawContent: '',
              frontmatter: const {},
              origin: origin,
              formulaDocument: recipe('recipe', 'RD900603'));
      for (final f in [
        formula(DataOrigin.official, '产品配方/recipe.md'),
        formula(DataOrigin.user, '产品配方/recipe.md')
      ]) {
        expect(
            FormulaAssociationIndex(productCatalog: [p], formulas: [f])
                .forProduct(p),
            isEmpty);
        expect(linkedFormulasForProduct(p, [f], productCatalog: [p]), isEmpty);
      }
      final own = formula(DataOrigin.user, 'user/产品配方/recipe.md');
      expect(
          FormulaAssociationIndex(productCatalog: [p], formulas: [own])
              .forProduct(p),
          [own]);
      expect(linkedFormulasForProduct(p, [own], productCatalog: [p]), [own]);
    }
  });
}

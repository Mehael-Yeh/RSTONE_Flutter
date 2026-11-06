// Synthetic records only, shared protocol validation remains strict.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/utils/formula_association.dart';
import 'support/sync_fixture.dart';
import 'personal_formula_sources_test.dart' show recipe;
import 'personal_edit_transaction_test.dart' show InterruptedStorage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('cleanup failure reports completed recipe and keeps the reminder recoverable', () async {
    final f = SignedFixture(); await f.initialize(); final base = await f.memoryStorage();
    final s = InterruptedStorage(base); final a = await f.app(s);
    await f.publish(1, {'产品列表/RD974004.md': product('synthetic')}); await a.sync!.synchronize();
    await a.addFormulaDraft('SyntheticSales740006');
    final draft = a.formulas.single;
    s.failRemoveKey = draft.filePath;
    await expectLater(a.completeFormulaDraft(draft, recipe(draft.fileName, 'RD974004')), completion(isFalse));
    await a.reloadUserItems();
    expect(a.formulas, hasLength(2));
    expect(a.formulas.where((p) => p.formulaDocument != null), hasLength(1));
    expect(a.formulas.where((p) => p.isFormulaDraft), hasLength(1));
    s.failRemoveKey = null;
    await a.deleteManualItem(a.formulas.singleWhere((p) => p.isFormulaDraft));
    expect(a.formulas.single.formulaDocument, isNotNull);
    a.dispose(); await base.close();
  });
  test('application and full recipe creation refuse casefold collisions without overwriting', () async {
    final f = SignedFixture(); await f.initialize(); final s = await f.memoryStorage(); final a = await f.app(s);
    await a.addApplicationMarkdown(name: 'SyntheticSales740001', markdown: 'original');
    await expectLater(a.addApplicationMarkdown(name: 'syntheticsales740001', markdown: 'changed'), throwsStateError);
    expect(await s.readText('user/产品应用/SyntheticSales740001.md'), 'original');
    await f.publish(1, {'产品列表/RD974001.md': product('synthetic')}); await a.sync!.synchronize();
    await a.addFormulaDocument(recipe('SyntheticSales740002', 'RD974001'));
    final original = await s.readText('user/产品配方/SyntheticSales740002.md');
    await expectLater(a.addFormulaDocument(recipe('SyntheticSales740002', 'RD974001')), throwsStateError);
    expect(await s.readText('user/产品配方/SyntheticSales740002.md'), original);
    a.dispose(); await s.close();
  });

  test('drafts reject unsafe names and duplicates, coexist with same-name official, never associate, export as draft', () async {
    final f = SignedFixture(); await f.initialize(); final s = await f.memoryStorage(); final a = await f.app(s);
    for (final name in ['', ' ', '../Synthetic740003', 'Synthetic740003/child', 'Synthetic740003\\child', 'Synthetic740003\n', 'CON', '.Synthetic740003', 'Synthetic740003?']) {
      await expectLater(a.addFormulaDraft(name), throwsA(anything));
      expect(await s.keys('user/配方草稿/'), isEmpty);
    }
    await f.publish(1, {'产品列表/RD974002.md': product('synthetic'), '产品配方/RD974002.md': utf8.decode(utf8.encode('---\n关联产品: "[[RD974002]]"\n---\n| synthetic | 1 |'))});
    expect(await a.sync!.synchronize(), isTrue);
    final officialRaw = a.formulas.single.rawContent;
    await a.addFormulaDraft('RD974002');
    await expectLater(a.addFormulaDraft('rd974002'), throwsStateError);
    await a.reloadUserItems();
    expect(a.formulas, hasLength(2));
    expect(a.formulas.singleWhere((p) => p.origin == DataOrigin.official).rawContent, officialRaw);
    final draft = a.formulas.singleWhere((p) => p.isFormulaDraft);
    expect(draft.formulaDocument, isNull); expect(draft.formulaProductRecords, isNull);
    expect(linkedFormulasForProduct(a.products.single, [draft], productCatalog: a.products), isEmpty);
    expect(FormulaAssociationIndex(productCatalog: a.products, formulas: [draft]).forProduct(a.products.single), isEmpty);
    final zip = ZipDecoder().decodeBytes((await a.exportMarkdownArchive())!);
    expect(zip.files.single.name, '配方草稿/RD974002.md');
    expect(jsonDecode(utf8.decode(zip.files.single.content as List<int>)), {'schema': 'personal-recipe-draft/1', 'title': 'RD974002'});
    await expectLater(a.addFormulaMarkdown(name: 'SyntheticSales740004', markdown: draft.rawContent), throwsFormatException);
    final draftRaw = draft.rawContent;
    await a.deleteManualItem(draft);
    expect(a.formulas.single.origin, DataOrigin.official);
    // Draft semantics are path+origin bound: never inferred from content elsewhere.
    expect(() => ProductItem.fromMdContent('user/配方草稿/RD974002.md',
        draftRaw, origin: DataOrigin.official), throwsFormatException);
    expect(ProductItem.fromMdContent('产品配方/RD974002.md', draftRaw,
        origin: DataOrigin.official).isFormulaDraft, isFalse);
    a.dispose(); await s.close();
  });

  test('failed draft write, invalid target, stale completion and collision preserve originals', () async {
    final f = SignedFixture(); await f.initialize(); final base = await f.memoryStorage(); final s = InterruptedStorage(base); final a = await f.app(s);
    s.failWriteKey = 'user/配方草稿/SyntheticSales740005.md';
    await expectLater(a.addFormulaDraft('SyntheticSales740005'), throwsStateError);
    expect(a.formulas, isEmpty);
    s.failWriteKey = null;
    await a.addFormulaDraft('SyntheticSales740005');
    final draft = a.formulas.single;
    await expectLater(a.completeFormulaDraft(draft, recipe(draft.fileName, 'RD974003')), throwsFormatException);
    expect(a.formulas.single.isFormulaDraft, isTrue);
    await f.publish(1, {'产品列表/RD974003.md': product('synthetic')}); await a.sync!.synchronize();
    await a.reloadUserItems();
    await expectLater(a.completeFormulaDraft(draft, recipe(draft.fileName, 'RD974003')), throwsStateError);
    await expectLater(a.deleteManualItem(draft), throwsStateError);
    final current = a.formulas.single;
    s.failWriteKey = 'user/产品配方/SyntheticSales740005.md';
    await expectLater(a.completeFormulaDraft(current, recipe(current.fileName, 'RD974003')), throwsStateError);
    expect(await base.readText(current.filePath), current.rawContent);
    expect(await base.keys('user/record-links/'), isEmpty);
    s.failWriteKey = null;
    await a.addFormulaDocument(recipe(current.fileName, 'RD974003'));
    final full = await base.readText('user/产品配方/SyntheticSales740005.md');
    await expectLater(a.completeFormulaDraft(current, recipe(current.fileName, 'RD974003')), throwsStateError);
    expect(await base.readText(current.filePath), current.rawContent);
    expect(await base.readText('user/产品配方/SyntheticSales740005.md'), full);
    a.dispose(); await s.close();
  });
}

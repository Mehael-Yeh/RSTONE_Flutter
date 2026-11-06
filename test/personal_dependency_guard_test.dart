import 'dart:convert';
import 'dart:io';
import 'package:rst_flutter/data_sync/storage/native_storage.dart';
import 'package:rst_flutter/data_sync/storage/storage_adapter.dart';
import 'package:rst_flutter/utils/formula_protocol_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rst_flutter/models/formula_document.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'support/sync_fixture.dart';
import 'formula_structured_test.dart' show specimen;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final native in [false, true]) {
    for (final schema in ['rstone-recipe/1', 'rstone-recipe/2']) {
      for (final role in ['owner', 'associated']) {
        for (final binding in ['saved', 'absent', 'corrupt']) {
          test(
              '$schema $role $binding native=$native stays byte exact on refusal',
              () async {
            final f = SignedFixture();
            await f.initialize();
            final dir = native
                ? await Directory.systemTemp.createTemp('dependency-')
                : null;
            final StorageAdapter s = native
                ? await NativeStorage.open(root: dir!)
                : await f.memoryStorage();
            addTearDown(() async {
              await s.close();
              if (dir != null) await dir.delete(recursive: true);
            });
            var a = await f.app(s);
            await a.addProductMarkdown(
                code: 'RS87654321-Q5', markdown: product('owner'));
            await a.addProductMarkdown(
                code: 'RD990002', markdown: product('participant'));
            final m = specimen()..['schema'] = schema;
            m['associatedProducts'] = ['RS87654321-Q5', 'RD990002'];
            final d = FormulaDocument.fromJson(m);
            await a.addFormulaDocument(d);
            final key = 'user/record-links/产品配方/${d.title}.md.json';
            if (binding == 'absent') await s.remove(key);
            if (binding == 'corrupt') await s.writeText(key, '{bad');
            a.dispose();
            a = await f.app(s);
            final p = a.products.firstWhere((p) =>
                p.fileName == (role == 'owner' ? 'RS87654321-Q5' : 'RD990002'));
            final prefs = PreferencesService();
            await prefs.initialize();
            await prefs.saveProductNote(p.displayName, 'unchanged');
            final notes = (await SharedPreferences.getInstance())
                .getString('product_notes');
            final bytes = {
              for (final k in await s.keys('user/'))
                k: base64Encode((await s.read(k))!)
            };
            expect(a.formulas, hasLength(1));
            await expectLater(
                a.updateProductMarkdown(
                    item: p, code: 'RS999990', markdown: 'changed'),
                throwsStateError);
            expect({
              for (final k in await s.keys('user/'))
                k: base64Encode((await s.read(k))!)
            }, bytes);
            expect(
                (await SharedPreferences.getInstance())
                    .getString('product_notes'),
                notes);
            expect(prefs.getProductNote(p.displayName), 'unchanged');
            expect(a.formulas, hasLength(1));
            // Same-name saves remain valid even with dependencies.
            await a.updateProductMarkdown(
                item: p, code: p.fileName, markdown: product('field edit'));
            final reopened = await f.app(s);
            expect(reopened.formulas, hasLength(1));
            expect(reopened.quarantinedFormulas, isEmpty);
          });
        }
      }
    }
  }
  for (final target in ['RS87654321', 'RS87654321-Q50', 'RS87654321-Q5-X']) {
    test('unrelated full grade $target renames with note migration', () async {
      final f = SignedFixture();
      await f.initialize();
      final s = await f.memoryStorage();
      final a = await f.app(s);
      await a.addProductMarkdown(
          code: 'RS87654321-Q5', markdown: product('owner'));
      await a.addFormulaDocument(FormulaDocument.fromJson(specimen()));
      await a.addProductMarkdown(code: target, markdown: product('unrelated'));
      final p = a.products.firstWhere((p) => p.fileName == target);
      final prefs = PreferencesService();
      await prefs.initialize();
      await prefs.saveProductNote(target, 'move');
      await a.updateProductMarkdown(
          item: p, code: 'RS999990', markdown: 'edited');
      expect(prefs.getProductNote('RS999990'), 'move');
      expect(prefs.getProductNote(target), isEmpty);
      expect((await f.app(s)).formulas, hasLength(1));
    });
  }
  for (final boundToUser in [false, true]) {
    test(
        'same-code official fallback respects source binding user=$boundToUser',
        () async {
      final f = SignedFixture();
      await f.initialize();
      final s = await f.memoryStorage();
      final a = await f.app(s);
      await f.publish(1, {'产品列表/RS87654321-Q5.md': product('official')});
      expect(await a.sync!.synchronize(), isTrue);
      if (!boundToUser) {
        await a.addFormulaDocument(FormulaDocument.fromJson(specimen()));
      }
      await a.addProductMarkdown(
          code: 'RS87654321-Q5', markdown: product('overlay'));
      if (boundToUser) {
        await a.addFormulaDocument(FormulaDocument.fromJson(specimen()));
      }
      final edit = a.updateProductMarkdown(
          item: a.products.single, code: 'RS999990', markdown: 'new');
      if (boundToUser) {
        await expectLater(edit, throwsStateError);
      } else {
        await edit;
      }
      final reopened = await f.app(s);
      expect(reopened.formulas, hasLength(1));
      expect(reopened.quarantinedFormulas, isEmpty);
    });
  }
  for (final legacy in [
    '---\n关联产品: "[[RS87654321-Q5]]"\n---\n',
    '| 原料编号 | 投入数 |\n| --- | --- |\n| [[产品列表/RS87654321-Q5.md]] | 1 |'
  ]) {
    test('legacy semantic reference refuses rename: $legacy', () async {
      final f = SignedFixture();
      await f.initialize();
      final s = await f.memoryStorage();
      await s.writeText('user/产品列表/RS87654321-Q5.md', product('personal'));
      await s.writeText('user/产品配方/legacy.md', legacy);
      final a = await f.app(s);
      await expectLater(
          a.updateProductMarkdown(
              item: a.products.single, code: 'RS999990', markdown: 'new'),
          throwsStateError);
      expect((await f.app(s)).formulas, hasLength(1));
    });
  }
  test('quarantined unknown recipe blocks only rename, not same-name edit',
      () async {
    final f = SignedFixture();
    await f.initialize();
    final s = await f.memoryStorage();
    await s.writeText('user/产品列表/RS87654321-Q5.md', product('personal'));
    final invalid = utf8
        .decode(
            FormulaProtocolCodec.encode(FormulaDocument.fromJson(specimen())))
        .replaceFirst('rstone-recipe/1', 'rstone-recipe/99');
    await s.writeText('user/产品配方/unknown.md', invalid);
    final a = await f.app(s);
    expect(a.quarantinedFormulas, hasLength(1));
    await expectLater(
        a.updateProductMarkdown(
            item: a.products.single, code: 'RS999990', markdown: 'new'),
        throwsStateError);
    await a.updateProductMarkdown(
        item: a.products.single, code: 'RS87654321-Q5', markdown: 'field edit');
    expect(await s.readText('user/产品配方/unknown.md'), invalid);
  });
  test(
      'dependent personal owner refuses rename before any storage or note change',
      () async {
    final f = SignedFixture();
    await f.initialize();
    final s = await f.memoryStorage();
    final a = await f.app(s);
    await a.addProductMarkdown(
        code: 'RS87654321-Q5', markdown: product('personal'));
    await a.addFormulaDocument(FormulaDocument.fromJson(specimen()));
    final p = a.products.single;
    final prefs = PreferencesService();
    await prefs.initialize();
    await prefs.saveProductNote(p.displayName, 'exact note');
    final before = {
      for (final k in await s.keys('user/')) k: base64Encode((await s.read(k))!)
    };
    expect(a.formulas, hasLength(1));
    await expectLater(
        a.updateProductMarkdown(
            item: p, code: 'RS99999999', markdown: product('edit')),
        throwsStateError);
    expect(a.formulas, hasLength(1));
    expect({
      for (final k in await s.keys('user/')) k: base64Encode((await s.read(k))!)
    }, before);
    expect(prefs.getAllProductNotes(), {p.displayName: 'exact note'});
    final reopened = await f.app(s);
    expect(reopened.formulas, hasLength(1));
    expect(reopened.quarantinedFormulas, isEmpty);
  });
}

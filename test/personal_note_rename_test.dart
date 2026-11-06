import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('rename migrates note and old name reuse cannot inherit it', () async {
    final f = SignedFixture(); await f.initialize();
    final s = await f.memoryStorage(); final app = await f.app(s);
    final prefs = PreferencesService(); await prefs.initialize();
    await app.addProductMarkdown(code: 'Alpha', markdown: 'original');
    await prefs.saveProductNote('Alpha', 'private annotation');
    await app.updateProductMarkdown(item: app.products.single, code: 'Beta', markdown: 'edited');
    expect(prefs.getProductNote('Beta'), 'private annotation');
    expect(prefs.getProductNote('Alpha'), isEmpty);
    await app.addProductMarkdown(code: 'Alpha', markdown: 'different record');
    await app.reloadUserItems(); await app.reloadUserItems();
    expect(prefs.getProductNote('Alpha'), isEmpty);
    expect(prefs.getProductNote('Beta'), 'private annotation');
  });

  test('different target note refuses rename without any changed bytes', () async {
    final f = SignedFixture(); await f.initialize();
    final s = await f.memoryStorage(); final app = await f.app(s);
    final prefs = PreferencesService(); await prefs.initialize();
    await app.addProductMarkdown(code: 'Alpha', markdown: 'original');
    await prefs.saveProductNote('Alpha', 'source');
    await prefs.saveProductNote('Beta', 'different target');
    await expectLater(app.updateProductMarkdown(item: app.products.single, code: 'Beta', markdown: 'edited'), throwsStateError);
    expect(await s.readText('user/产品列表/Alpha.md'), 'original');
    expect(await s.readText('user/产品列表/Beta.md'), isNull);
    expect(prefs.getAllProductNotes(), {'Alpha': 'source', 'Beta': 'different target'});
  });

  for (final source in ['', 'same', 'different']) {
    test('target annotation is never adopted or overwritten source=$source', () async {
      final f = SignedFixture(); await f.initialize();
      final s = await f.memoryStorage(); final app = await f.app(s);
      final prefs = PreferencesService(); await prefs.initialize();
      await app.addProductMarkdown(code: 'Alpha', markdown: 'original');
      await prefs.saveProductNote('Alpha', source);
      await prefs.saveProductNote('Beta', 'same');
      final before = (await SharedPreferences.getInstance()).getString('product_notes');
      await expectLater(app.updateProductMarkdown(item: app.products.single, code: 'Beta', markdown: 'edited'),
          throwsA(isA<StateError>().having((e) => e.message.toString(), 'message', contains('目标名称已有备注'))));
      expect((await SharedPreferences.getInstance()).getString('product_notes'), before);
      expect(await s.readText('user/产品列表/Alpha.md'), 'original');
      expect(await s.readText('user/产品列表/Beta.md'), isNull);
      expect(await s.readText('user/transactions/product-edit.json'), isNull);
    });
  }

  test('same name leaves note bytes intact and case-only rename moves exact key', () async {
    final f = SignedFixture(); await f.initialize();
    final s = await f.memoryStorage(); final app = await f.app(s);
    final native = await SharedPreferences.getInstance();
    const raw = '{ "Alpha": "source", "Other": "  untouched spaces  " }';
    await native.setString('product_notes', raw);
    await native.setString('unrelated_preference', 'preserved');
    await app.addProductMarkdown(code: 'Alpha', markdown: 'original');
    await app.updateProductMarkdown(item: app.products.single, code: 'Alpha', markdown: 'same path');
    expect(native.getString('product_notes'), raw);
    await app.updateProductMarkdown(item: app.products.single, code: 'ALPHA', markdown: 'new case');
    final prefs = PreferencesService(); await prefs.initialize();
    expect(prefs.getAllProductNotes(), {'ALPHA': 'source', 'Other': '  untouched spaces  '});
    expect(native.getString('unrelated_preference'), 'preserved');
  });

  test('official overlay without annotations can rename without touching official bytes', () async {
    final f = SignedFixture(); await f.initialize();
    final s = await f.memoryStorage(); final app = await f.app(s);
    await f.publish(1, {'产品列表/Alpha.md': product('official')});
    await app.sync!.synchronize();
    final official = app.products.single.rawContent;
    await app.addProductMarkdown(code: 'Alpha', markdown: 'personal overlay');
    await app.updateProductMarkdown(item: app.products.single, code: 'Beta', markdown: 'edited');
    expect(app.products.firstWhere((p) => p.fileName == 'Alpha').rawContent, official);
    expect(app.products.firstWhere((p) => p.fileName == 'Beta').rawContent, 'edited');
    final prefs = PreferencesService(); await prefs.initialize();
    expect(prefs.getAllProductNotes(), isEmpty);
  });

  for (final moved in [false, true]) {
    test('pending dual-store journal recovers notes moved=$moved idempotently', () async {
      final f = SignedFixture(); await f.initialize();
      final s = await f.memoryStorage();
      final before = jsonEncode({'Alpha': 'source', 'Other': 'untouched'});
      final after = jsonEncode({'Beta': 'source', 'Other': 'untouched'});
      final nativePrefs = await SharedPreferences.getInstance();
      await nativePrefs.setString('product_notes', moved ? after : before);
      await s.writeText('user/产品列表/Beta.md', 'edited');
      await s.writeText('user/transactions/product-edit.json', jsonEncode({
        'version': 2, 'oldPath': 'user/产品列表/Alpha.md',
        'newPath': 'user/产品列表/Beta.md', 'before': 'original', 'after': 'edited',
        'notes': {'before': before, 'after': after},
      }));
      final app = await f.app(s);
      expect(nativePrefs.getString('product_notes'), before);
      expect(await s.readText('user/产品列表/Alpha.md'), 'original');
      expect(await s.readText('user/产品列表/Beta.md'), isNull);
      expect(await s.readText('user/transactions/product-edit.json'), isNull);
      await app.reloadUserItems();
      expect(nativePrefs.getString('product_notes'), before);
    });
  }

  test('official overlay note is ambiguous and must not be moved', () async {
    final f = SignedFixture(); await f.initialize();
    final s = await f.memoryStorage(); final app = await f.app(s);
    await f.publish(1, {'产品列表/Alpha.md': product('official')});
    await app.sync!.synchronize();
    final prefs = PreferencesService(); await prefs.initialize();
    await prefs.saveProductNote('Alpha', 'official annotation');
    await app.addProductMarkdown(code: 'Alpha', markdown: 'personal overlay');
    await expectLater(app.updateProductMarkdown(item: app.products.single, code: 'Beta', markdown: 'edited'), throwsStateError);
    expect(await s.readText('user/产品列表/Alpha.md'), 'personal overlay');
    expect(await s.readText('user/产品列表/Beta.md'), isNull);
    expect(prefs.getAllProductNotes(), {'Alpha': 'official annotation'});
  });
}

import 'dart:typed_data';
import 'dart:async';
import 'dart:io';
import 'package:rst_flutter/data_sync/storage/native_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/data_sync/storage/storage_adapter.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'support/sync_fixture.dart';

class InterruptedStorage extends StorageAdapter {
  final StorageAdapter base;
  String? failWriteKey, failRemoveKey;
  bool dead = false, crash = false;
  Completer<void>? removeGate, removeStarted;
  InterruptedStorage(this.base);
  void check(String key, String? target) {
    if (dead || key == target) {
      if (crash) dead = true;
      throw StateError('injected storage interruption');
    }
  }

  @override
  Future<Uint8List?> read(String key) {
    check(key, null);
    return base.read(key);
  }

  @override
  Future<void> write(String key, Uint8List bytes) {
    check(key, failWriteKey);
    return base.write(key, bytes);
  }

  @override
  Future<void> remove(String key) async {
    check(key, failRemoveKey);
    if (key.endsWith('/旧名称.md') && removeGate != null) {
      removeStarted!.complete();
      await removeGate!.future;
    }
    await base.remove(key);
  }

  @override
  Future<List<String>> keys(String prefix) {
    check(prefix, null);
    return base.keys(prefix);
  }

  @override
  Future<String?> fingerprint(String key) => base.fingerprint(key);
  @override
  Future<void> commitActive(Uint8List? expected, Uint8List next) =>
      base.commitActive(expected, next);
  @override
  Future<void> close() async {}
}

Future<void> edit(dynamic app, ProductItem item, String name, String text) =>
    app.updateProductMarkdown(item: item, code: name, markdown: text)
        as Future<void>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('pending deletion excludes concurrent personal mutations', () async {
    final f = SignedFixture();
    await f.initialize();
    final base = await f.memoryStorage();
    final s = InterruptedStorage(base);
    final a = await f.app(s);
    await a.addProductMarkdown(code: '旧名称', markdown: 'old');
    s.removeGate = Completer<void>();
    s.removeStarted = Completer<void>();
    final deleting = a.deleteManualItem(a.products.single);
    await s.removeStarted!.future;
    try {
      await expectLater(
          a.addProductMarkdown(code: '新名称', markdown: 'new'), throwsStateError);
    } finally {
      s.removeGate!.complete();
      await deleting;
    }
  });
  test('edit renames own product, preserves other records and survives reload',
      () async {
    final f = SignedFixture();
    await f.initialize();
    final s = await f.memoryStorage();
    final a = await f.app(s);
    await a.addProductMarkdown(code: '自定义', markdown: product('before'));
    await a.addProductMarkdown(code: '其它', markdown: product('other'));
    final p = a.products.firstWhere((p) => p.fileName == '自定义');
    await edit(a, p, 'ABC', product('after'));
    expect(await s.readText('user/产品列表/自定义.md'), isNull);
    expect(await s.readText('user/产品列表/ABC.md'), product('after'));
    final reloaded = await f.app(s);
    expect(
        reloaded.products.map((p) => p.fileName), containsAll(['ABC', '其它']));
    expect(await s.readText('user/产品列表/其它.md'), product('other'));
    await expectLater(edit(a, p, 'stale', 'no'), throwsStateError);
  });
  test('casefold conflicts and official edits are refused', () async {
    final f = SignedFixture();
    await f.initialize();
    final s = await f.memoryStorage();
    final a = await f.app(s);
    await f.publish(1, {'产品列表/RD900301.md': product('official')});
    await a.sync!.synchronize();
    await expectLater(edit(a, a.products.single, 'no', 'no'), throwsStateError);
    await a.addProductMarkdown(code: 'Alpha', markdown: 'alpha');
    await a.addProductMarkdown(code: 'Beta', markdown: 'beta');
    await expectLater(
        edit(a, a.products.firstWhere((p) => p.fileName == 'Alpha'), 'bETA',
            'no'),
        throwsStateError);
    expect(await s.readText('user/产品列表/Beta.md'), 'beta');
  });
  test('same-path and case-only edits persist without duplicate records',
      () async {
    final f = SignedFixture();
    await f.initialize();
    final s = await f.memoryStorage();
    final a = await f.app(s);
    await a.addProductMarkdown(code: 'Alpha', markdown: 'before');
    await edit(a, a.products.single, 'Alpha', 'same path');
    expect(a.products.single.rawContent, 'same path');
    await edit(a, a.products.single, 'ALPHA', 'case changed');
    await a.reloadUserItems();
    expect(a.products.single.fileName, 'ALPHA');
    expect(await s.readText('user/产品列表/Alpha.md'), isNull);
  });
  for (final native in [false, true]) {
    for (final stage in [
      'journal-write',
      'new-write',
      'old-remove',
      'journal-remove'
    ]) {
      for (final crash in [false, true]) {
        test(
            '$stage failure native=$native crash=$crash recovers old bytes without overwriting neighbours',
            () async {
          final f = SignedFixture();
          await f.initialize();
          final directory = native
              ? await Directory.systemTemp.createTemp('personal-transaction-')
              : null;
          final base = native
              ? await NativeStorage.open(root: directory!)
              : await f.memoryStorage();
          addTearDown(() async {
            await base.close();
            if (directory != null) await directory.delete(recursive: true);
          });
          final s = InterruptedStorage(base);
          final a = await f.app(s);
          await a.addProductMarkdown(code: '旧名称', markdown: 'old bytes');
          await a.addProductMarkdown(code: '其它', markdown: 'neighbour bytes');
          if (stage == 'new-write') s.failWriteKey = 'user/产品列表/新名称.md';
          if (stage == 'journal-write') {
            s.failWriteKey = 'user/transactions/product-edit.json';
          }
          if (stage == 'old-remove') s.failRemoveKey = 'user/产品列表/旧名称.md';
          if (stage == 'journal-remove') {
            s.failRemoveKey = 'user/transactions/product-edit.json';
          }
          s.crash = crash;
          await expectLater(
              edit(a, a.products.firstWhere((p) => p.fileName == '旧名称'), '新名称',
                  'new bytes'),
              throwsStateError);
          if (stage == 'old-remove' && crash) {
            expect(await base.readText('user/产品列表/新名称.md'), 'new bytes');
            expect(await base.readText('user/transactions/product-edit.json'),
                isNotNull);
          }
          final reload = await f.app(base);
          expect(await base.readText('user/产品列表/旧名称.md'), 'old bytes');
          expect(await base.readText('user/产品列表/新名称.md'), isNull);
          expect(await base.readText('user/产品列表/其它.md'), 'neighbour bytes');
          expect(reload.products.map((p) => p.fileName),
              containsAll(['旧名称', '其它']));
          expect(await base.readText('user/transactions/product-edit.json'),
              isNull);
        });
      }
    }
  }
}

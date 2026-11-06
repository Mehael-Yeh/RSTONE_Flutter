import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

import 'package:rst_flutter/services/personal_product_transaction.dart';

import 'personal_edit_transaction_test.dart' show InterruptedStorage;

import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/data_sync/storage/native_storage.dart';
import 'package:rst_flutter/data_sync/storage/storage_adapter.dart';

import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final native in [false, true]) {
    for (final changed in [
      '---\r\nbody  \r\n',
      '\uFEFF---\r\nbody \r\n',
      '\uFEFF---\nbody  \n',
      '\uFEFF---\r\nother  \r\n'
    ]) {
      test(
          'exact stale and journal conflict native=$native changed=${jsonEncode(changed)}',
          () async {
        final f = SignedFixture();
        await f.initialize();
        final directory = native
            ? await Directory.systemTemp.createTemp('bom-conflict-')
            : null;
        final StorageAdapter storage = native
            ? await NativeStorage.open(root: directory!)
            : await f.memoryStorage();
        addTearDown(() async {
          await storage.close();
          if (directory != null) await directory.delete(recursive: true);
        });
        const oldPath = 'user/产品列表/Alpha.md';
        const newPath = 'user/产品列表/Beta.md';
        const before = '\uFEFF---\r\nbody  \r\n';
        const after = '\uFEFFafter\n';
        await storage.writeText(oldPath, before);
        final app = await f.app(storage);
        final item = app.products.single;
        await storage.writeText(oldPath, changed);
        await expectLater(
            app.updateProductMarkdown(
                item: item, code: 'Beta', markdown: after),
            throwsA(isA<StateError>().having(
                (e) => e.message, 'message', 'stale-personal-product')));
        expect(await storage.read(oldPath), raw(changed));
        expect(await storage.read(newPath), isNull);
        expect(
            await storage.read(PersonalProductTransaction.journalKey), isNull);
        final journal = jsonEncode({
          'version': 1,
          'oldPath': oldPath,
          'newPath': newPath,
          'before': before,
          'after': after
        });
        await storage.writeText(PersonalProductTransaction.journalKey, journal);
        final tx = PersonalProductTransaction(storage);
        await expectLater(
            tx.recover(),
            throwsA(isA<StateError>().having(
                (e) => e.message, 'message', 'personal-transaction-conflict')));
        expect(await storage.read(oldPath), raw(changed));
        expect(await storage.read(PersonalProductTransaction.journalKey),
            raw(journal));
        // Also reject a foreign target, keeping both files and the journal.
        await storage.writeText(oldPath, before);
        await storage.writeText(newPath, changed);
        await expectLater(tx.recover(), throwsStateError);
        expect(await storage.read(oldPath), raw(before));
        expect(await storage.read(newPath), raw(changed));
        expect(await storage.read(PersonalProductTransaction.journalKey),
            raw(journal));
      });
    }
    for (final name in ['Alpha', 'ALPHA', 'Beta']) {
      for (final beforeBom in [false, true]) {
        for (final afterBom in [false, true]) {
          test(
              'journal exact rollback native=$native target=$name beforeBom=$beforeBom afterBom=$afterBom',
              () async {
            final f = SignedFixture();
            final directory = native
                ? await Directory.systemTemp.createTemp('bom-journal-')
                : null;
            final StorageAdapter storage = native
                ? await NativeStorage.open(root: directory!)
                : await f.memoryStorage();
            addTearDown(() async {
              await storage.close();
              if (directory != null) await directory.delete(recursive: true);
            });
            const oldPath = 'user/产品列表/Alpha.md';
            final newPath = 'user/产品列表/$name.md';
            final before = '${beforeBom ? '\uFEFF' : ''}before  \r\n';
            final after = '${afterBom ? '\uFEFF' : ''}after\r\n';
            await storage.writeText(newPath, after);
            await storage.writeText(
                PersonalProductTransaction.journalKey,
                jsonEncode({
                  'version': 1,
                  'oldPath': oldPath,
                  'newPath': newPath,
                  'before': before,
                  'after': after
                }));
            final tx = PersonalProductTransaction(storage);
            await tx.recover();
            expect(await storage.read(oldPath), raw(before));
            if (oldPath != newPath) expect(await storage.read(newPath), isNull);
            expect(await storage.read(PersonalProductTransaction.journalKey),
                isNull);
            await tx.recover();
            expect(await storage.read(oldPath), raw(before));
          });
        }
      }
    }
    for (final stage in [
      'journal-write',
      'new-write',
      'old-remove',
      'journal-remove'
    ]) {
      for (final crash in [false, true]) {
        for (final rename in [false, true]) {
          if (!rename && stage == 'old-remove') continue;
          test(
              'BOM rollback native=$native stage=$stage crash=$crash rename=$rename',
              () async {
            final f = SignedFixture();
            await f.initialize();
            final directory = native
                ? await Directory.systemTemp.createTemp('bom-recovery-')
                : null;
            final StorageAdapter base = native
                ? await NativeStorage.open(root: directory!)
                : await f.memoryStorage();
            addTearDown(() async {
              await base.close();
              if (directory != null) await directory.delete(recursive: true);
            });
            const oldPath = 'user/产品列表/Alpha.md';
            final newPath = rename ? 'user/产品列表/Beta.md' : oldPath;
            const before =
                '\uFEFF---\r\ntags: [synthetic]\r\n---\r\nBefore  \r\n';
            const after = '\uFEFF---\r\ntags: [synthetic]\r\n---\r\nAfter\r\n';
            const neighbour = 'user/产品列表/Other.md';
            await base.writeText(oldPath, before);
            await base.writeText(neighbour, 'neighbour');
            final official = 'official/objects/${'a' * 64}';
            await base.writeText(official, before);
            final s = InterruptedStorage(base)..crash = crash;
            final app = await f.app(s);
            if (stage == 'journal-write') {
              s.failWriteKey = PersonalProductTransaction.journalKey;
            }
            if (stage == 'new-write') s.failWriteKey = newPath;
            if (stage == 'old-remove') s.failRemoveKey = oldPath;
            if (stage == 'journal-remove') {
              s.failRemoveKey = PersonalProductTransaction.journalKey;
            }
            await expectLater(
                app.updateProductMarkdown(
                    item: app.products.firstWhere((p) => p.fileName == 'Alpha'),
                    code: rename ? 'Beta' : 'Alpha',
                    markdown: after),
                throwsStateError);
            if (stage != 'journal-write' && crash) {
              expect(await base.read(PersonalProductTransaction.journalKey),
                  isNotNull);
            }
            final reload = await f.app(base);
            expect(await base.read(oldPath), raw(before));
            if (rename) expect(await base.read(newPath), isNull);
            expect(await base.read(neighbour), raw('neighbour'));
            expect(await base.read(official), raw(before));
            expect(
                reload.products
                    .firstWhere((p) => p.fileName == 'Alpha')
                    .rawContent,
                before);
            expect(
                await base.read(PersonalProductTransaction.journalKey), isNull);
          });
        }
      }
    }
    for (final rename in [false, true]) {
      test('BOM service edit native=$native rename=$rename', () async {
        final f = SignedFixture();
        await f.initialize();
        final directory = native
            ? await Directory.systemTemp.createTemp('bom-transaction-')
            : null;
        final StorageAdapter storage = native
            ? await NativeStorage.open(root: directory!)
            : await f.memoryStorage();
        addTearDown(() async {
          await storage.close();
          if (directory != null) await directory.delete(recursive: true);
        });
        const oldPath = 'user/产品列表/Alpha.md';
        const before = '\uFEFF---\r\ntags: [synthetic]\r\n---\r\nBefore\r\n';
        const after = '\uFEFF---\r\ntags: [synthetic]\r\n---\r\nAfter\r\n';
        await storage.writeText(oldPath, before);
        // Use the real adapter decoding contract, not a text-preserving fake.
        expect(await storage.readText(oldPath), before.substring(1));
        final app = await f.app(storage);
        await f.publish(1, {'产品列表/Alpha.md': product('official-synthetic')});
        expect(await app.sync!.synchronize(), isTrue);
        final officialPath = app.sync!.snapshot.products.single.rawContent;
        final officialKeys = await storage.keys('official/objects/');
        final officialBytes = {
          for (final key in officialKeys) key: await storage.read(key)
        };
        expect(app.products.single.rawContent, before);
        await app.updateProductMarkdown(
            item: app.products.single,
            code: rename ? 'Beta' : 'Alpha',
            markdown: after);
        final target = rename ? 'user/产品列表/Beta.md' : oldPath;
        expect(await storage.read(target), raw(after));
        if (rename) expect(await storage.read(oldPath), isNull);
        final reload = await f.app(storage);
        final reloadedPersonal = reload.products
            .firstWhere((p) => p.fileName == (rename ? 'Beta' : 'Alpha'));
        expect(reloadedPersonal.rawContent, after);
        expect(app.sync!.snapshot.products.single.rawContent, officialPath);
        for (final key in officialKeys) {
          expect(await storage.read(key), officialBytes[key]);
        }
        expect(
            await storage.read('user/transactions/product-edit.json'), isNull);
      });
    }
  }
}

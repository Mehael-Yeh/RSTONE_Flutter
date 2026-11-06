import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rst_flutter/data_sync/storage/native_storage.dart';
import 'package:rst_flutter/services/personal_product_transaction.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'support/sync_fixture.dart';

class InterruptedNotes extends PreferencesService {
  final bool afterWrite, crash;
  bool dead = false;
  InterruptedNotes({required this.afterWrite, required this.crash});
  @override
  Future<void> applyProductNoteChange(ProductNoteChange change,
      {required bool rollback}) async {
    if (dead) throw StateError('simulated prefs outage');
    if (rollback) return super.applyProductNoteChange(change, rollback: true);
    if (afterWrite) await super.applyProductNoteChange(change, rollback: false);
    if (crash) dead = true;
    throw StateError('simulated prefs interruption');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final native in [false, true]) {
    for (final afterWrite in [false, true]) {
      for (final crash in [false, true]) {
        test('prefs interruption native=$native afterWrite=$afterWrite crash=$crash', () async {
          final f = SignedFixture(); await f.initialize();
          final directory = native ? await Directory.systemTemp.createTemp('synthetic-notes-') : null;
          final storage = native ? await NativeStorage.open(root: directory!) : await f.memoryStorage();
          addTearDown(() async { await storage.close(); if (directory != null) await directory.delete(recursive: true); });
          final prefs = InterruptedNotes(afterWrite: afterWrite, crash: crash);
          await prefs.initialize();
          await prefs.saveProductNote('Alpha', 'source');
          await prefs.saveProductNote('Other', 'unrelated');
          final change = prefs.prepareProductNoteRename('Alpha', 'Beta', officialSource: false)!;
          await storage.writeText('user/产品列表/Alpha.md', 'before');
          await expectLater(PersonalProductTransaction(storage, preferences: prefs).edit(
            'user/产品列表/Alpha.md', 'user/产品列表/Beta.md', 'before', 'after', noteChange: change), throwsStateError);
          if (crash) expect(await storage.readText(PersonalProductTransaction.journalKey), isNotNull);
          await PersonalProductTransaction(storage).recover();
          await PersonalProductTransaction(storage).recover();
          expect(await storage.readText('user/产品列表/Alpha.md'), 'before');
          expect(await storage.readText('user/产品列表/Beta.md'), isNull);
          expect(prefs.getAllProductNotes(), {'Alpha': 'source', 'Other': 'unrelated'});
        });
      }
    }
  }

  test('recovery never overwrites later notes or unrelated file changes', () async {
    final f = SignedFixture(); await f.initialize(); final storage = await f.memoryStorage();
    final prefs = PreferencesService(); await prefs.initialize();
    await prefs.saveProductNote('Alpha', 'source');
    final change = prefs.prepareProductNoteRename('Alpha', 'Beta', officialSource: false)!;
    await storage.writeText('user/产品列表/Beta.md', 'after');
    final raw = jsonEncode({'version': 2, 'oldPath': 'user/产品列表/Alpha.md',
      'newPath': 'user/产品列表/Beta.md', 'before': 'before', 'after': 'after', 'notes': change.toJson()});
    await storage.writeText(PersonalProductTransaction.journalKey, raw);
    await prefs.applyProductNoteChange(change, rollback: false);
    await prefs.saveProductNote('Beta', 'later different annotation');
    final snapshot = prefs.getAllProductNotes();
    await expectLater(PersonalProductTransaction(storage).recover(), throwsStateError);
    expect(prefs.getAllProductNotes(), snapshot);
    expect(await storage.readText('user/产品列表/Beta.md'), 'after');
    expect(await storage.readText('user/产品列表/Alpha.md'), isNull);
    expect(await storage.readText(PersonalProductTransaction.journalKey), raw);
    await prefs.saveProductNote('Beta', 'source');
    await storage.writeText('user/产品列表/Beta.md', 'later different file');
    await expectLater(PersonalProductTransaction(storage).recover(), throwsStateError);
    expect(prefs.getProductNote('Beta'), 'source');
    expect(await storage.readText('user/产品列表/Beta.md'), 'later different file');
    expect(await storage.readText(PersonalProductTransaction.journalKey), raw);
  });
}

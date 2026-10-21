import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/data_sync/storage/native_storage.dart';
import 'package:rst_flutter/data_sync/storage/legacy_migration_native.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late NativeStorage store;
  late SignedFixture fixture;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('rstone-native-test-');
    store = await NativeStorage.open(root: root);
    fixture = SignedFixture();
    await fixture.initialize();
  });
  tearDown(() async {
    await store.close();
    // Only this test's verified temporary directory is removed.
    if (root.absolute.path.startsWith(Directory.systemTemp.absolute.path) &&
        root.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('rstone-native-test-')) {
      await root.delete(recursive: true);
    }
  });

  test(
      'native SQLite commit survives close/reopen and deleted CAS objects stay invisible',
      () async {
    final app = await fixture.app(store);
    await fixture.publish(
        1, {'产品列表/RS1.md': product('水性'), '产品列表/RS2.md': product('UV')});
    expect(await app.sync!.synchronize(), isTrue, reason: app.sync!.error);
    await fixture.publish(2, {'产品列表/RS2.md': product('UV')});
    expect(await app.sync!.synchronize(), isTrue, reason: app.sync!.error);
    expect((await store.keys('official/objects/')).length, 2);
    app.dispose();
    await store.close();
    store = await NativeStorage.open(root: root);
    final reopened = await fixture.app(store);
    expect(reopened.products.map((p) => p.fileName).toList(), ['RS2']);
    expect(reopened.sync!.current!.sequence, 2);
    fixture.transport.requests.clear();
    expect(await reopened.sync!.synchronize(), isTrue);
    expect(fixture.transport.objectRequests, isEmpty);
    reopened.dispose();
  });

  test('native object tampering is repaired and user overlay is independent',
      () async {
    final app = await fixture.app(store);
    await fixture.publish(1, {'产品列表/RS1.md': product('水性')});
    expect(await app.sync!.synchronize(), isTrue);
    await app.addProductMarkdown(code: 'RS1', markdown: product('个人'));
    final hash = app.sync!.current!.files.single.sha256;
    await File('${root.path}/official/objects/$hash')
        .writeAsString('broken', flush: true);
    expect(await app.sync!.synchronize(), isTrue, reason: app.sync!.error);
    expect(app.products.single.origin, DataOrigin.user);
    expect(app.products.single.tags, ['个人']);
    app.dispose();
  });

  test(
      'migration is idempotent, preserves unmarked originals and imports only personal files and rules',
      () async {
    final products = Directory('${root.path}/产品列表');
    await products.create();
    final apps = Directory('${root.path}/产品应用');
    await apps.create();
    await File('${products.path}/RS1.md').writeAsString(product('个人'));
    await File('${products.path}/RS2.md').writeAsString(product('旧官方'));
    final unmarked = File('${products.path}/e\u0301.md');
    await unmarked.writeAsString(product('未标记的旧文件'));
    await File('${apps.path}/个人方案.md').writeAsString('[[RS1]]');
    await File('${root.path}/manual_items.json').writeAsString(jsonEncode({
      'products': ['RS1'],
      'applications': ['个人方案']
    }));
    await File('${root.path}/tag_alias_rules.custom.txt')
        .writeAsString('自定义 -> 别名');
    await migrateLegacyData(store, legacyRoot: root);
    final firstKeys = await store.keys('user/');
    await store.writeText('user/产品列表/RS1.md', product('已修改'));
    await migrateLegacyData(store, legacyRoot: root);
    expect(await store.keys('user/'), firstKeys);
    expect(await store.readText('user/产品列表/RS1.md'), product('已修改'));
    expect(await store.readText('user/custom_rules/tag_alias_rules.custom.txt'),
        '自定义 -> 别名');
    expect(await store.readText('migration/quarantine/产品列表/RS2.md'), isNull);
    expect(await File('${products.path}/RS2.md').exists(), isTrue);
    expect(await unmarked.exists(), isTrue);
    final app = await fixture.app(store);
    expect(app.products.map((p) => p.fileName).toList(), ['RS1']);
    expect(app.applications.single.origin, DataOrigin.user);
    expect(app.products.any((p) => p.fileName == 'RS2'), isFalse);
    app.dispose();
  });
}

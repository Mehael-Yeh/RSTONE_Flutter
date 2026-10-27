import 'package:flutter_test/flutter_test.dart';
import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('TDS never falls back from a full suffix to the base grade', () async {
    final fixture = SignedFixture();
    await fixture.initialize();
    final store = await fixture.memoryStorage();
    final app = await fixture.app(store);
    addTearDown(() async {
      app.dispose();
      await store.close();
    });
    await fixture.publish(1, {'产品TDS/RS90001.TDS.md': '# synthetic base TDS'});
    expect(await app.sync!.synchronize(), isTrue);
    expect(app.tdsForProduct('RS90001-2'), isNull);
  });

  test('TDS resolves only for the identical full grade', () async {
    final fixture = SignedFixture();
    await fixture.initialize();
    final store = await fixture.memoryStorage();
    final app = await fixture.app(store);
    addTearDown(() async {
      app.dispose();
      await store.close();
    });
    await fixture
        .publish(1, {'产品TDS/RS90002-2.TDS.md': '# synthetic variant TDS'});
    expect(await app.sync!.synchronize(), isTrue);
    expect(app.tdsForProduct('RS90002-2'), '# synthetic variant TDS');
    expect(app.tdsForProduct('RS90002'), isNull);
    expect(app.tdsForProduct('RS90002-2 '), '# synthetic variant TDS');
  });

  test('TDS never swaps RD and RS prefixes', () async {
    final fixture = SignedFixture();
    await fixture.initialize();
    final store = await fixture.memoryStorage();
    final app = await fixture.app(store);
    addTearDown(() async {
      app.dispose();
      await store.close();
    });
    await fixture.publish(1, {'产品TDS/RD90003.TDS.md': '# synthetic lab TDS'});
    expect(await app.sync!.synchronize(), isTrue);
    expect(app.tdsForProduct('RS90003'), isNull);
    expect(app.tdsForProduct('RD90003'), '# synthetic lab TDS');
  });

  test('TDS keeps punctuation and letter suffixes significant', () async {
    final fixture = SignedFixture();
    await fixture.initialize();
    final store = await fixture.memoryStorage();
    final app = await fixture.app(store);
    addTearDown(() async {
      app.dispose();
      await store.close();
    });
    await fixture.publish(1, {
      '产品TDS/RD90004-4-亮.TDS.md': '# synthetic matt-free TDS',
      '产品TDS/RS90005 TF.TDS.md': '# synthetic space-grade TDS',
    });
    expect(await app.sync!.synchronize(), isTrue);
    expect(app.tdsForProduct('RD90004-4-亮'), '# synthetic matt-free TDS');
    expect(app.tdsForProduct('RD90004-4'), isNull);
    expect(app.tdsForProduct('RD900044'), isNull);
    expect(app.tdsForProduct('RD90004.4.亮'), isNull);
    expect(app.tdsForProduct('RS90005 TF'), '# synthetic space-grade TDS');
    expect(app.tdsForProduct('RS90005TF'), isNull);
  });

  test('TDS basename repeated under different folders stays ambiguous',
      () async {
    final fixture = SignedFixture();
    await fixture.initialize();
    final store = await fixture.memoryStorage();
    final app = await fixture.app(store);
    addTearDown(() async {
      app.dispose();
      await store.close();
    });
    await fixture.publish(1, {
      '产品TDS/甲/RS90006.TDS.md': '# synthetic folder A',
      '产品TDS/乙/RS90006.TDS.md': '# synthetic folder B',
    });
    expect(await app.sync!.synchronize(), isTrue);
    expect(app.tdsForProduct('RS90006'), isNull);
  });

  test('root TDS does not bypass duplicate-basename ambiguity', () async {
    final fixture = SignedFixture();
    await fixture.initialize();
    final store = await fixture.memoryStorage();
    final app = await fixture.app(store);
    addTearDown(() async {
      app.dispose();
      await store.close();
    });
    await fixture.publish(1, {
      '产品TDS/RS90010.TDS.md': '# synthetic root',
      '产品TDS/archive/RS90010.TDS.md': '# synthetic archive',
    });
    expect(await app.sync!.synchronize(), isTrue);
    expect(app.tdsForProduct('RS90010'), isNull);
  });

  test('TDS keeps T, TF and v02 suffixes independent', () async {
    final fixture = SignedFixture();
    await fixture.initialize();
    final store = await fixture.memoryStorage();
    final app = await fixture.app(store);
    addTearDown(() async {
      app.dispose();
      await store.close();
    });
    await fixture.publish(1, {
      '产品TDS/RS90007-T.TDS.md': '# synthetic T',
      '产品TDS/RS90008TF.TDS.md': '# synthetic TF',
      '产品TDS/RD90009v02.TDS.md': '# synthetic v02',
    });
    expect(await app.sync!.synchronize(), isTrue);
    expect(app.tdsForProduct('RS90007'), isNull);
    expect(app.tdsForProduct('RS90007-TF'), isNull);
    expect(app.tdsForProduct('rs90007-t'), '# synthetic T');
    expect(app.tdsForProduct('RS90008'), isNull);
    expect(app.tdsForProduct('RS90008TF'), '# synthetic TF');
    expect(app.tdsForProduct('RD90009'), isNull);
    expect(app.tdsForProduct('RD90009V02'), '# synthetic v02');
  });
}

// Diagnostic RED only: not included in the delivery patch's passing suite.
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('personal overlay must not inherit the same-code official formula',
      () async {
    final fixture = SignedFixture();
    await fixture.initialize();
    final storage = await fixture.memoryStorage();
    final app = await fixture.app(storage);
    await fixture.publish(1, {
      '产品列表/RD900101.md': product('official900001'),
      '产品配方/RD900101-底.md':
          '---\n关联产品: "[[RD900101]]"\n---\n| 原料编号 | 数量 |\n| --- | --- |\n| [[RD900101]] | 1 |',
    });
    expect(await app.sync!.synchronize(), isTrue);
    final official = app.products.single;
    expect(official.origin, DataOrigin.official);
    expect(app.formulaAssociations.forProduct(official), hasLength(1));
    await app.addProductMarkdown(
        code: 'RD900101', markdown: product('personal900001'));
    final personal = app.products.single;
    expect(personal.origin, DataOrigin.user);
    expect(app.sync!.snapshot.products.single.origin, DataOrigin.official);
    expect(app.formulaAssociations.forProduct(personal), isEmpty,
        reason:
            'the visible personal overlay cannot inherit official recipe ownership');
  });
  test('same-name personal add must not overwrite an existing record',
      () async {
    final fixture = SignedFixture();
    await fixture.initialize();
    final storage = await fixture.memoryStorage();
    final app = await fixture.app(storage);
    await app.addProductMarkdown(code: 'RS900201', markdown: 'original900001');
    await expectLater(
        () => app.addProductMarkdown(
            code: 'RS900201', markdown: 'replacement900002'),
        throwsA(anything));
    expect(await storage.readText('user/产品列表/RS900201.md'), 'original900001');
  });
}

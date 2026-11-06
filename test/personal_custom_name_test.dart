// Synthetic personal names; signed official validation is intentionally unchanged.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'product_scroll_regression_test.dart' as ui_fixture;
import 'package:rst_flutter/models/product_item.dart';
import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('personal add form has no official grade-prefix hint',
      (tester) async {
    await ui_fixture.mount(tester, n: 20);
    final state = tester.state<ScrollableState>(find.byType(Scrollable).first);
    OverscrollNotification(
            metrics: state.position, context: state.context, overscroll: -80)
        .dispatch(state.context);
    ScrollEndNotification(metrics: state.position, context: state.context)
        .dispatch(state.context);
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增产品信息'));
    await tester.pumpAndSettle();
    expect(find.text('以 RD 或 RS 开头'), findsNothing);
    expect(find.text('输入自定义产品名称'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });
  test(
      'custom Chinese and ABC personal names persist without a grade prefix or case rewrite',
      () async {
    final fixture = SignedFixture();
    await fixture.initialize();
    final storage = await fixture.memoryStorage();
    final app = await fixture.app(storage);
    for (final name in ['自定义900001', 'Abc900002']) {
      await app.addProductMarkdown(
          code: name, markdown: '---\n工程师: Synthetic900003\n---\n');
      expect(app.products.singleWhere((p) => p.fileName == name).origin,
          DataOrigin.user);
      expect(await storage.readText('user/产品列表/$name.md'), isNotNull);
    }
    await app.reloadUserItems();
    expect(app.products.map((p) => p.fileName),
        containsAll(['自定义900001', 'Abc900002']));
    app.dispose();
    await storage.close();
  });
  test(
      'empty control traversal and nonportable personal leaf names never persist',
      () async {
    final fixture = SignedFixture();
    await fixture.initialize();
    final storage = await fixture.memoryStorage();
    final app = await fixture.app(storage);
    for (final name in [
      '',
      '  ',
      '../900001',
      'ABC900001/nested',
      'ABC900001\\nested',
      'ABC900001\n',
      'ABC900001\u007f',
      'ABC900001?',
      '.ABC900001',
      'CON'
    ]) {
      await expectLater(
          () => app.addProductMarkdown(code: name, markdown: 'untouched'),
          throwsA(anything),
          reason: name);
      expect(await storage.keys('user/产品列表/'), isEmpty);
      expect(app.products, isEmpty);
    }
    app.dispose();
    await storage.close();
  });
}

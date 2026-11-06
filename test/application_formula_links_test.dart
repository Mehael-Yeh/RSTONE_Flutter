import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/widgets/product_detail_sheet.dart';
import 'package:rst_flutter/widgets/product_detail/structured_formula_card.dart';
import 'package:rst_flutter/widgets/product_detail/application_formula_links.dart';
import 'package:rst_flutter/widgets/product_detail/formula_png_renderer.dart';
import 'package:rst_flutter/widgets/product_detail/formula_presentation.dart';
import 'package:rst_flutter/widgets/product_detail/formula_pinned_table.dart';
import 'formula_structured_test.dart' show specimen, document;

ProductItem recipe(String name, String marker,
    {DataOrigin origin = DataOrigin.unknown}) {
  final m = specimen()
    ..['title'] = name
    ..['recipeId'] = 'SYNTH-$marker';
  m['rows'][0][4] = marker;
  return ProductItem.fromMdContent(
      '${origin == DataOrigin.user ? 'user/' : ''}产品配方/$name.md', document(m),
      origin: origin);
}

Future<void> mount(
    WidgetTester tester, ProductItem app, List<ProductItem> recipes,
    {double width = 1200, double height = 1800}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: ProductDetailSheet(
              product: app, productCatalog: const [], formulas: recipes))));
  await tester.pumpAndSettle();
}

Future<void> tapMarkdownGlyph(WidgetTester tester, String target) async {
  final field = find.byWidgetPredicate((w) =>
      w is SelectableText &&
      (w.textSpan?.toPlainText() ?? w.data ?? '').contains(target));
  expect(field, findsOneWidget);
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  final text = tester.widget<SelectableText>(field).textSpan!.toPlainText();
  final editable = tester.state<EditableTextState>(
      find.descendant(of: field, matching: find.byType(EditableText)));
  final boxes = editable.renderEditable.getBoxesForSelection(TextSelection(
      baseOffset: text.indexOf(target),
      extentOffset: text.indexOf(target) + target.length));
  expect(boxes, isNotEmpty);
  await tester.tapAt(
      editable.renderEditable.localToGlobal(boxes.first.toRect().center));
  await tester.pumpAndSettle();
}

void main() {
  for (final origin in [DataOrigin.official, DataOrigin.user]) {
    testWidgets('same-name recipes obey application source $origin',
        (tester) async {
      final official =
          recipe('RS900006-银', 'SOURCE-OFFICIAL', origin: DataOrigin.official);
      final personal =
          recipe(official.fileName, 'SOURCE-PERSONAL', origin: DataOrigin.user);
      final app = ProductItem.fromMdContent(
          '${origin == DataOrigin.user ? 'user/' : ''}产品应用/来源.md',
          '---\n底漆: [[产品配方/${official.fileName}]]\n---\n',
          origin: origin);
      await mount(tester, app, [personal, official]);
      await tester.tap(find.text(official.fileName));
      await tester.pumpAndSettle();
      final selected = tester
          .widget<StructuredFormulaCard>(find.byType(StructuredFormulaCard));
      expect(
          identical(
              selected.view.document,
              origin == DataOrigin.user
                  ? personal.formulaDocument
                  : official.formulaDocument),
          isTrue);
    });
  }
  testWidgets(
      'unknown empty and malformed targets never create a clickable recipe',
      (tester) async {
    final f = recipe('RS900007-银', 'KNOWN');
    for (final raw in [
      '',
      '[[产品列表/${f.fileName}]]',
      '[[产品配方/../${f.fileName}]]',
      '[[[${f.fileName}]]]',
      '[[产品配方/RS900007-黑]]'
    ]) {
      final app =
          ProductItem.fromMdContent('产品应用/拒绝.md', '---\n底漆: "$raw"\n---\n');
      await mount(tester, app, [f]);
      expect(find.byType(StructuredFormulaCard), findsNothing);
      expect(
          find.byWidgetPredicate((w) =>
              w is Text && w.style?.decoration == TextDecoration.underline),
          findsNothing);
    }
  });
  testWidgets(
      'replacing an application never retains a missing previous selection',
      (tester) async {
    final a = recipe('RS900003-底', 'REPLACE-A'),
        b = recipe('RS900003-银', 'REPLACE-B');
    final app = ProductItem.fromMdContent(
        '产品应用/旧.md', '---\n底漆: [[产品配方/${a.fileName}]]\n---\n');
    await mount(tester, app, [a, b]);
    final next = ProductItem.fromMdContent(
        '产品应用/新.md', '---\n面漆: [[产品配方/${b.fileName}]]\n---\n');
    await mount(tester, next, [a, b]);
    expect(
        tester
            .widget<StructuredFormulaCard>(find.byType(StructuredFormulaCard))
            .view
            .document
            .recipeId,
        'SYNTH-REPLACE-B');
  });
  test(
      'exact namespace and provenance reject unknown malformed and ambiguous references',
      () {
    final app = ProductItem.fromMdContent('产品应用/合成.md', '',
        origin: DataOrigin.official);
    final f = recipe('RS900004-银', 'OFFICIAL', origin: DataOrigin.official);
    final personal = recipe(f.fileName, 'PERSONAL', origin: DataOrigin.user);
    for (final target in [
      '',
      '产品列表/${f.fileName}',
      '其它目录/${f.fileName}',
      '产品配方/../${f.fileName}',
      '产品配方/sub/${f.fileName}',
      r'产品配方\RS900004-银',
      '产品配方/${f.fileName}.md',
      '[[[${f.fileName}]]]',
      '[[${f.fileName}|别名]]',
      '[[${f.fileName}#标题]]',
      'RS900004',
      'RS900004-黑'
    ]) {
      expect(resolveApplicationFormula(app, [f, personal], target), isNull,
          reason: target);
    }
    expect(resolveApplicationFormula(app, [personal, f], '产品配方/${f.fileName}'),
        same(f));
    final userApp = ProductItem.fromMdContent('user/产品应用/合成.md', '',
        origin: DataOrigin.user);
    expect(resolveApplicationFormula(userApp, [f, personal], f.fileName),
        same(personal));
    expect(resolveApplicationFormula(userApp, [f], f.fileName), same(f));
    expect(resolveApplicationFormula(app, [personal], f.fileName), isNull);
    expect(
        resolveApplicationFormula(
            userApp,
            [
              personal,
              recipe(f.fileName, 'DUP-USER', origin: DataOrigin.user),
              f
            ],
            f.fileName),
        isNull);
    expect(
        resolveApplicationFormula(
            userApp,
            [
              f,
              recipe(f.fileName, 'DUP-OFFICIAL', origin: DataOrigin.official)
            ],
            f.fileName),
        isNull);
    expect(
        resolveApplicationFormula(
            app,
            [f, recipe(f.fileName, 'DUP', origin: DataOrigin.official)],
            f.fileName),
        isNull);
    for (final text in [
      '[[[${f.fileName}]]]',
      '\\\\[[${f.fileName}]]',
      '[[其它目录/${f.fileName}]]',
      '[[产品配方/../${f.fileName}]]'
    ]) {
      expect(applicationFormulaTokens(app, [f], text), isEmpty, reason: text);
    }
  });
  testWidgets('multiple scalar tokens keep independent exact click targets',
      (tester) async {
    final a = recipe('RS900005-底', 'MULTI-A'),
        b = recipe('RS900005-银', 'MULTI-B');
    final app = ProductItem.fromMdContent('产品应用/多引用.md',
        '---\n底漆: "[[产品配方/${a.fileName}]] + [[产品配方/${b.fileName}]]"\n---\n');
    await mount(tester, app, [a, b]);
    await tapMarkdownGlyph(tester, b.fileName);
    expect(
        tester
            .widget<StructuredFormulaCard>(find.byType(StructuredFormulaCard))
            .view
            .document
            .recipeId,
        'SYNTH-MULTI-B');
    expect(app.rawContent, contains('[[产品配方/${a.fileName}]]'));
  });
  testWidgets(
      'body table and prose links select their exact recipe without metadata',
      (tester) async {
    final a = recipe('RS900002-底', 'BODY-A'),
        b = recipe('RS900002-银', 'BODY-B');
    final app = ProductItem.fromMdContent('产品应用/正文.md',
        '---\n---\n先用 [[产品配方/${a.fileName}]]。\n\n| 层位 | 配方 |\n| --- | --- |\n| 面漆 | [[产品配方/${b.fileName}]] |\n');
    await mount(tester, app, [a, b]);
    expect(find.byType(StructuredFormulaCard), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    await tapMarkdownGlyph(tester, b.fileName);
    expect(
        tester
            .widget<StructuredFormulaCard>(find.byType(StructuredFormulaCard))
            .view
            .document
            .recipeId,
        'SYNTH-BODY-B');
    expect(find.textContaining('[['), findsNothing);
  });
  for (final qualified in [false, true]) {
    testWidgets(
        '${qualified ? 'qualified' : 'bare'} metadata retains underline and tap switches exact BOM and clipboard',
        (tester) async {
      final a = recipe('RS900001-底', 'FIRST'),
          b = recipe('RS900001-银', 'SECOND');
      final prefix = qualified ? '产品配方/' : '';
      final app = ProductItem.fromMdContent('产品应用/合成.md',
          '---\n底漆: "[[$prefix${a.fileName}]]"\n面漆: "[[$prefix${b.fileName}]]"\n---\n');
      expect(app.topCoat,
          '$prefix${b.fileName}'); // raw target still survives model parsing
      await mount(tester, app, [a, b, recipe('RS900001-黑', 'UNREFERENCED')],
          width: 390, height: 844);
      expect(find.byType(StructuredFormulaCard), findsOneWidget);
      expect(
          tester
              .widget<StructuredFormulaCard>(find.byType(StructuredFormulaCard))
              .view
              .document
              .recipeId,
          'SYNTH-FIRST');
      final link = find.text(b.fileName);
      expect(link, findsOneWidget);
      expect(tester.widget<Text>(link).style!.decoration,
          TextDecoration.underline);
      await tester.tap(link);
      await tester.pumpAndSettle();
      final card = tester
          .widget<StructuredFormulaCard>(find.byType(StructuredFormulaCard));
      expect(identical(card.view.document, b.formulaDocument), isTrue);
      String? copied;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'];
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.tap(find.byTooltip('复制配方五列'));
      await tester.pumpAndSettle();
      expect(copied, contains('SECOND'));
      expect(copied, isNot(contains('FIRST')));
      expect(card.view.cells[1][4], 'SECOND');
      await (FontLoader('sans-serif')
            ..addFont(rootBundle.load('assets/fonts/MicrosoftYaHei.ttf')))
          .load();
      const share = MethodChannel('dev.fluttercommunity.plus/share');
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      List<int>? shared;
      String? subject;
      String? sharedPath;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          paths, (call) async => Directory.systemTemp.path);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(share,
          (call) async {
        if (call.method == 'shareFiles') {
          final args = call.arguments as Map;
          sharedPath = (args['paths'] as List).single as String;
          shared = File(sharedPath!).readAsBytesSync();
          subject = args['subject'] as String?;
        }
        return 'success';
      });
      addTearDown(() {
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(paths, null);
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(share, null);
      });
      await tester.runAsync(() async {
        final expected = await FormulaPngRenderer.render(card.view);
        final previous = await FormulaPngRenderer.render(
            FormulaDisplayView(a.formulaDocument!));
        await tester.tap(find.byTooltip('分享配方图片'));
        for (var i = 0; i < 100 && shared == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(shared, orderedEquals(expected));
        expect(shared, isNot(orderedEquals(previous)));
        expect(subject, startsWith(b.fileName));
        expect(sharedPath, endsWith('${b.formulaDocument!.recipeId}.png'));
      });
      expect(find.textContaining('产品配方/'), findsNothing);
      final table = find.byType(FormulaPinnedTable);
      final grid = tester.widget<FormulaPinnedTable>(table);
      expect(tester.getSize(table).height,
          closeTo(grid.heights.fold<double>(0, (a, b) => a + b), .1));
      expect(
          find.descendant(
              of: table,
              matching: find.byWidgetPredicate((w) =>
                  w is Scrollable &&
                  (w.axisDirection == AxisDirection.down ||
                      w.axisDirection == AxisDirection.up))),
          findsNothing);
      expect(
          find.descendant(
              of: table,
              matching: find.byWidgetPredicate(
                  (w) => w is Scrollbar || w is RawScrollbar)),
          findsNothing);
      await tester.ensureVisible(table);
      await tester.pumpAndSettle();
      final horizontal =
          find.byKey(ValueKey('recipe-scroll:${b.formulaDocument!.recipeId}'));
      final firstCell = find
          .byKey(ValueKey('recipe-cell:${b.formulaDocument!.recipeId}:1:0'));
      final x = tester.getTopLeft(firstCell).dx;
      await tester.drag(horizontal, const Offset(-2000, 0));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(firstCell).dx, x);
      final lastCell = find
          .byKey(ValueKey('recipe-cell:${b.formulaDocument!.recipeId}:1:4'));
      expect(tester.getRect(lastCell).right, lessThanOrEqualTo(390));
      expect(tester.takeException(), isNull);
    });
  }
}

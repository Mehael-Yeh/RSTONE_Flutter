import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

List<TextSpan> ingredientLinks(WidgetTester tester, Finder scope) {
  final links = <TextSpan>[];
  void visit(InlineSpan span) {
    if (span is TextSpan) {
      if (span.recognizer is TapGestureRecognizer) links.add(span);
      span.children?.forEach(visit);
    }
  }

  for (final rich in tester.widgetList<RichText>(
      find.descendant(of: scope, matching: find.byType(RichText)))) {
    visit(rich.text);
  }
  return links;
}

/// Hit actual glyphs, not a callback or the prefix/whole paragraph midpoint.
Future<void> tapIngredientText(WidgetTester tester, Finder scope, String text,
    {int occurrence = 0}) async {
  for (final element in find
      .descendant(of: scope, matching: find.byType(RichText))
      .evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final plain = paragraph.text.toPlainText();
    var start = -1;
    for (var i = 0; i <= occurrence; i++) {
      start = plain.indexOf(text, start + 1);
      if (start < 0) break;
    }
    if (start < 0) continue;
    final box = paragraph
        .getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: start + text.length))
        .first
        .toRect();
    await tester.tapAt(paragraph.localToGlobal(box.center));
    await tester.pumpAndSettle();
    return;
  }
  fail('No actual ingredient glyphs for $text');
}

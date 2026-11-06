import '../../models/product_item.dart';

/// Application references are exact recipe identities, never resin associations.
/// Strip only the known namespace, not arbitrary paths or malformed wiki syntax.
ProductItem? resolveApplicationFormula(
    ProductItem application, List<ProductItem> formulas, String value) {
  var target = value.trim();
  if (RegExp(r'^\[\[[^\[\]\r\n]+\]\]$').hasMatch(target)) {
    target = target.substring(2, target.length - 2);
  }
  if (target.startsWith('产品配方/')) {
    target = target.substring('产品配方/'.length);
  }
  if (target.isEmpty ||
      target == '.' ||
      target == '..' ||
      RegExp(r'[/\\\[\]#|\x00-\x1f\x7f]').hasMatch(target)) {
    return null;
  }
  bool personal(ProductItem p) =>
      p.origin == DataOrigin.user ||
      (p.origin == DataOrigin.unknown && p.filePath.startsWith('user/'));
  final matches = formulas
      .where((f) => f.folder == '产品配方' && f.fileName == target)
      .toList();
  final sameSource =
      matches.where((f) => personal(f) == personal(application)).toList();
  if (sameSource.isNotEmpty) {
    return sameSource.length == 1 ? sameSource.single : null;
  }
  // An explicit user application reference may use an existing official recipe.
  // Official applications never borrow personal recipes; ambiguous targets fail.
  if (!personal(application)) return null;
  final official = matches.where((f) => !personal(f)).toList();
  return official.length == 1 ? official.single : null;
}

/// Use original scalar spelling so malformed brackets cannot be made valid by
/// the general-purpose model's display normalization. No facts are rewritten.
String applicationFormulaField(ProductItem app, String label, String fallback) {
  final lines = app.rawContent.split('\n');
  if (lines.isNotEmpty && lines.first.trim() == '---') {
    for (final line in lines.skip(1).takeWhile((l) => l.trim() != '---')) {
      if (!line.startsWith('$label:')) continue;
      var value = line.substring(label.length + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      return value;
    }
  }
  return fallback;
}

final _wiki = RegExp(r'\[\[[^\[\]\r\n]+\]\]');

/// Each legal token carries the original exact target separately from its label.
/// Unknown, escaped, nested and malformed tokens remain non-navigable text.
Iterable<({int start, int end, ProductItem formula})> applicationFormulaTokens(
    ProductItem app, List<ProductItem> formulas, String text) sync* {
  for (final m in _wiki.allMatches(text)) {
    if ((m.start > 0 &&
            (text[m.start - 1] == '[' || text[m.start - 1] == r'\')) ||
        (m.end < text.length && text[m.end] == ']')) {
      continue;
    }
    final recipe = resolveApplicationFormula(app, formulas, m[0]!);
    if (recipe != null) yield (start: m.start, end: m.end, formula: recipe);
  }
}

String applicationFormulaMarkdown(
    ProductItem app, List<ProductItem> formulas, String text) {
  final out = StringBuffer();
  var cursor = 0;
  for (final part in applicationFormulaTokens(app, formulas, text)) {
    out.write(text.substring(cursor, part.start));
    final label = part.formula.fileName
        .replaceAllMapped(RegExp(r'[\\`*_{}\[\]()#+.!<>]'), (m) => '\\${m[0]}');
    out.write(
        '[$label](application-recipe:${Uri.encodeComponent(part.formula.fileName)})');
    cursor = part.end;
  }
  out.write(text.substring(cursor));
  return out.toString();
}

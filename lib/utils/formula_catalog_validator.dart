import '../models/product_item.dart';
import '../models/formula_document.dart';

/// Entire catalogue gate. Shape decoding is not publication approval.
void validateFormulaCatalog(
    Iterable<ProductItem> products, Iterable<ProductItem> formulas,
    {bool requireStructured = false, bool official = true}) {
  final names = products.map((p) => p.fileName).toSet();
  final ids = <String>{};
  for (final item in formulas) {
    final d = item.formulaDocument;
    if (d == null) {
      if (requireStructured) {
        throw const FormatException('structured-recipe-required');
      }
      continue;
    }
    if (!ids.add(d.recipeId)) {
      throw const FormatException('duplicate-recipe-id');
    }
    validateFormulaReferences(d, names);
    if (official) {
      if (d.title != item.fileName) {
        throw const FormatException('recipe-title-path-mismatch');
      }
      final matches = names
          .where((n) => d.title == n || d.title.startsWith('$n-'))
          .toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      if (matches.isEmpty ||
          matches.first != d.ownerProduct ||
          !_tail.hasMatch(d.title.substring(d.ownerProduct.length))) {
        throw const FormatException('recipe-owner-path-mismatch');
      }
    }
    if (d.classification == 'main' &&
        !d.rows.any((r) => _positiveOwner(r, d.ownerProduct))) {
      throw const FormatException('main-owner-positive-ingredient-required');
    }
    // Every role must carry interpretable amounts: a negative, inverted or
    // unreadable quantity is a fact defect, not merely missing credit.
    if (!d.rows.every((r) => _validAmount(r[1]))) {
      throw const FormatException('invalid-recipe-amount');
    }
  }
}

void validateFormulaReferences(FormulaDocument d, Set<String> names) {
  if (!d.associatedProducts.every(names.contains)) {
    throw const FormatException('recipe-product-not-in-complete-catalog');
  }
}

// Closed existing use/editorial suffix grammar; longest registered full owner wins.
final _tail = RegExp(
    r'^(?:-(?:亮|哑|银|黑|底|处理剂|白|红|涂料|蓝|面漆))?(?:-(?:参考配方(?:-方案(?:[0-9]+|RS[0-9]+(?:-[A-Za-z0-9]+)*(?:-方案[0-9]+)?))?|方案(?:[0-9]+|RS[0-9]+(?:-[A-Za-z0-9]+)*)))?$');
// Decimal comparisons are exact even at the 4096-code-unit string boundary.
// This is an identity guard only; it never rewrites displayed amount strings.
int _decimalCompare(String a, String b) {
  List<String> parts(String value) {
    final p = value.split('.');
    return [
      p.first.replaceFirst(RegExp(r'^0+'), ''),
      p.length == 1 ? '' : p[1]
    ];
  }

  final left = parts(a), right = parts(b);
  if (left[0].length != right[0].length) {
    return left[0].length.compareTo(right[0].length);
  }
  final integral = left[0].compareTo(right[0]);
  if (integral != 0) return integral;
  final width =
      left[1].length > right[1].length ? left[1].length : right[1].length;
  return left[1].padRight(width, '0').compareTo(right[1].padRight(width, '0'));
}

final _amount =
    RegExp(r'^([0-9]+(?:\.[0-9]+)?)(?:\s*[-–~]\s*([0-9]+(?:\.[0-9]+)?))?$');
// Closed unknown-quantity vocabulary; same set as the Python publisher gate.
final _unknown = RegExp(
    r'^(?:适量|少量|若干|另加|按当量另加|开稀至可喷粘度|按NCO/OH=[0-9]+(?:\.[0-9]+)?另加|适量（NCO/OH=[0-9]+(?:\.[0-9]+)?-[0-9]+(?:\.[0-9]+)?）)$');
final _unknownRatio =
    RegExp(r'^适量（NCO/OH=([0-9]+(?:\.[0-9]+)?)-([0-9]+(?:\.[0-9]+)?)）$');
bool _validAmount(String amount) {
  final m = _amount.firstMatch(amount);
  if (m != null) return _decimalCompare(m[1]!, m[2] ?? m[1]!) <= 0;
  if (!_unknown.hasMatch(amount)) return false;
  final ratio = _unknownRatio.firstMatch(amount);
  if (ratio == null) return true;
  return RegExp(r'[1-9]').hasMatch(ratio[1]!) &&
      _decimalCompare(ratio[1]!, ratio[2]!) <= 0;
}
bool _positiveOwner(List<String> row, String owner) {
  final m = _amount.firstMatch(row[1]);
  if (m == null) return false;
  final low = m[1]!, high = m[2] ?? m[1]!;
  if (!RegExp(r'[1-9]').hasMatch(low) || _decimalCompare(low, high) > 0) {
    return false;
  }
  final material = row[0];
  if (material == owner ||
      material == '[[$owner]]' ||
      material == '主体树脂（[[$owner]]）') {
    return true;
  }
  final concentration =
      RegExp('^${RegExp.escape('[[$owner]]')}\\(([0-9]+(?:\\.[0-9]+)?)%\\)\$')
          .firstMatch(material);
  if (concentration == null) return false;
  final percent = concentration[1]!;
  return RegExp(r'[1-9]').hasMatch(percent) &&
      _decimalCompare(percent, '100') <= 0;
}

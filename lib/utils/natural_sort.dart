/// Natural sorting helpers used by product/application tables and indexes.
///
/// Compared with regular lexicographical sorting, digit runs are compared as
/// numbers first, then by digit-run length when the numeric value is equal.
/// This keeps product codes such as `RD824-8` before `RD1010-4`, and
/// `RD1011-5` before `RD1011-6` when sorting ascending.
int compareNaturalText(String a, String b) {
  final left = a.toLowerCase().trim();
  final right = b.toLowerCase().trim();
  var i = 0;
  var j = 0;

  while (i < left.length && j < right.length) {
    final leftCode = left.codeUnitAt(i);
    final rightCode = right.codeUnitAt(j);
    final leftIsDigit = _isAsciiDigit(leftCode);
    final rightIsDigit = _isAsciiDigit(rightCode);

    if (leftIsDigit && rightIsDigit) {
      final leftStart = i;
      final rightStart = j;
      while (i < left.length && _isAsciiDigit(left.codeUnitAt(i))) {
        i++;
      }
      while (j < right.length && _isAsciiDigit(right.codeUnitAt(j))) {
        j++;
      }

      final result = _compareDigitRuns(
        left.substring(leftStart, i),
        right.substring(rightStart, j),
      );
      if (result != 0) return result;
      continue;
    }

    if (leftCode != rightCode) {
      return leftCode.compareTo(rightCode);
    }
    i++;
    j++;
  }

  return left.length.compareTo(right.length);
}

bool _isAsciiDigit(int codeUnit) => codeUnit >= 48 && codeUnit <= 57;

int _compareDigitRuns(String a, String b) {
  final normalizedA = _stripLeadingZeros(a);
  final normalizedB = _stripLeadingZeros(b);

  if (normalizedA.length != normalizedB.length) {
    return normalizedA.length.compareTo(normalizedB.length);
  }

  final numericResult = normalizedA.compareTo(normalizedB);
  if (numericResult != 0) return numericResult;

  if (a.length != b.length) {
    return a.length.compareTo(b.length);
  }

  return a.compareTo(b);
}

String _stripLeadingZeros(String value) {
  final stripped = value.replaceFirst(RegExp(r'^0+'), '');
  return stripped.isEmpty ? '0' : stripped;
}

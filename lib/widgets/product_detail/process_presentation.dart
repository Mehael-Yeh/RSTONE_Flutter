/// Display projection only. Source steps and protocol bytes remain untouched.
/// Ambiguous/ragged space-separated blocks are emitted verbatim, never padded,
/// transposed or guessed. Proven rectangles use explicit labels, not spacing.
List<String> presentFormulaProcess(List<String> steps) {
  final output = <String>[];
  final separator = RegExp(r'[ \t]{2,}');
  List<String> fields(String text) => text.trim().split(separator);
  // A rectangle does not prove that its first instruction is a header.
  // Only known, ordered curing-table field sets may become labeled rows.
  const recognizedHeaders = [
    ['固化段类型', '波段标识', '推荐能量密度', '补充说明'],
    ['工段', '波段', '能量', '说明'],
  ];
  bool recognized(List<String> row) => recognizedHeaders.any((header) =>
      row.length == header.length &&
      List.generate(header.length, (c) => row[c] == header[c])
          .every((same) => same));
  var i = 0;
  while (i < steps.length) {
    final first = fields(steps[i]);
    if (first.length > 1) {
      var end = i + 1;
      while (end < steps.length && fields(steps[end]).length > 1) {
        end++;
      }
      final rows = steps.sublist(i, end).map(fields).toList();
      final rectangular = rows.length >= 3 &&
          first.length <= 6 &&
          first.toSet().length == first.length &&
          recognized(first) &&
          rows.every((row) =>
              row.length == first.length && row.every((v) => v.isNotEmpty)) &&
          rows.skip(1).every((row) =>
              List.generate(first.length, (c) => row[c] == first[c])
                  .contains(false));
      if (rectangular) {
        for (final row in rows.skip(1)) {
          output.add(List.generate(first.length, (c) => '${first[c]}：${row[c]}')
              .join('\n'));
        }
      } else {
        output.addAll(steps.sublist(i, end));
      }
      i = end;
      continue;
    }
    // Confirmed OCR split of the word 保温, with an explicit hold duration.
    // No blanket Chinese-line joining: numbered items, headings and unknown
    // words retain their original step boundaries.
    if (i + 1 < steps.length &&
        RegExp(r'[，,]保$').hasMatch(steps[i]) &&
        RegExp(r'^温\s*\d+(?:\.\d+)?\s*小时').hasMatch(steps[i + 1])) {
      output.add('${steps[i]}${steps[i + 1]}');
      i += 2;
    } else {
      output.add(steps[i]);
      i++;
    }
  }
  return List.unmodifiable(output);
}

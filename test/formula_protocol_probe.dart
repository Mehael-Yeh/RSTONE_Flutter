// Standalone Dart (no Flutter imports). Public synthetic shared golden only.
import 'dart:convert';
import 'dart:io';
import 'package:rst_flutter/utils/formula_protocol_codec.dart';

void check(bool ok, String name) {
  if (!ok) throw StateError(name);
}

void rejects(void Function() fn, String name) {
  var rejected = false;
  try {
    fn();
  } on FormatException {
    rejected = true;
  }
  check(rejected, name);
}

void main() {
  final cases = jsonDecode(File('test/fixtures/recipe_protocol/cases.json')
      .readAsStringSync())['cases'] as List;
  var accepted = 0;
  for (final c in cases) {
    final raw = base64Decode(c['rawBase64']);
    if (c['shapeAccepted'] == true) {
      final d = FormulaProtocolCodec.decode(raw);
      check(base64Encode(FormulaProtocolCodec.encode(d)) == c['rawBase64'],
          c['name']);
      check(
          FormulaProtocolCodec.canonicalJson(d.toJson()) ==
              FormulaProtocolCodec.canonicalJson(c['model']),
          'model ${c['name']}');
      accepted++;
    } else {
      rejects(() => FormulaProtocolCodec.decode(raw), c['name']);
    }
  }
  check(accepted == 6 && cases.length == 48, 'frozen case inventory');
  stdout.writeln(
      'PASS standalone Dart: 48 shared golden; 6 accepted; exact model + bytes');
}

// Standalone Dart cap and immutability boundary probes; no Flutter runtime.
import 'dart:convert';
import 'dart:io';
import 'package:rst_flutter/models/formula_document.dart';
import 'package:rst_flutter/utils/formula_protocol_codec.dart';
import 'formula_protocol_probe.dart' show check, rejects;

Map<String, dynamic> base() => jsonDecode(
    File('test/fixtures/recipe_protocol/valid.model.json').readAsStringSync());
void main(List<String> args) {
  var checks = 0;
  void roundTrip(Map<String, dynamic> m, String label) {
    final d = FormulaDocument.fromJson(m);
    final raw = FormulaProtocolCodec.encode(d);
    check(
        base64Encode(FormulaProtocolCodec.encode(
                FormulaProtocolCodec.decode(raw))) ==
            base64Encode(raw),
        label);
    checks++;
  }

  void invalid(Map<String, dynamic> m, String label) {
    rejects(
        () => FormulaProtocolCodec.encode(FormulaDocument.fromJson(m)), label);
    checks++;
  }

  roundTrip(
      base()..['preTable'] = ['x' * 4096, '😀' * 2048, '\t\n\u007f\u2028'],
      'utf16-exact');
  for (final bad in [
    'x' * 4097,
    '😀' * 2049,
    '\u0001',
    '\r',
    String.fromCharCode(0xd800),
    String.fromCharCode(0xdc00)
  ]) {
    invalid(base()..['preTable'] = [bad], 'invalid-scalar-or-length');
  }
  for (final field in ['rows', 'preTable', 'content', 'associatedProducts']) {
    dynamic item(int i) => switch (field) {
          'rows' => ['water', '0', '', '', ''],
          'preTable' => '',
          'content' => {'kind': 'note', 'text': ''},
          _ => i == 0 ? 'RS87654321-Q5' : 'RS${i + 100000}',
        };
    roundTrip(base()..[field] = List.generate(1000, item), '$field-exact1000');
    invalid(base()..[field] = List.generate(1001, item), '$field-over1000');
  }
  roundTrip(
      base()
        ..['content'] = [
          {'kind': 'process', 'label': 'steps', 'steps': List.filled(1000, '')}
        ],
      'steps-exact1000');
  invalid(
      base()
        ..['content'] = [
          {'kind': 'process', 'label': 'steps', 'steps': List.filled(1001, '')}
        ],
      'steps-over1000');
  final headerModel = base()..['preTable'] = [];
  var n = FormulaProtocolCodec.maxHeader -
      FormulaProtocolCodec.canonicalJson(headerModel).length;
  // Adding a string to [] costs two quotes and (except first) a comma.
  final parts = <String>[];
  while (n > 4099) {
    parts.add('a' * 4096);
    n -= 4096 + 2 + (parts.length == 1 ? 0 : 1);
  }
  parts.add('a' * (n - 2 - (parts.isEmpty ? 0 : 1)));
  headerModel['preTable'] = parts;
  check(
      FormulaProtocolCodec.canonicalJson(headerModel).length ==
          FormulaProtocolCodec.maxHeader,
      'header-boundary-construction');
  roundTrip(headerModel, 'header-exact512KiB');
  final raw =
      FormulaProtocolCodec.encode(FormulaDocument.fromJson(headerModel));
  final bigger = base()
    ..['preTable'] = [...parts.sublist(0, parts.length - 1), '${parts.last}x'];
  invalid(bigger, 'header-over512KiB');
  rejects(
      () => FormulaProtocolCodec.decode(
          List.filled(FormulaProtocolCodec.maxFile + 1, 32)),
      'file-over16MiB');
  checks++;
  rejects(
      () => FormulaProtocolCodec.decode(utf8
          .encode('---\n${' ' * (FormulaProtocolCodec.maxHeader + 1)}\n---\n')),
      'raw-header-over512KiB');
  checks++;
  dynamic deep = 'x';
  for (var i = 0; i < 17; i++) {
    deep = [deep];
  }
  rejects(
      () => FormulaProtocolCodec.decode(
          utf8.encode('---\n${jsonEncode(deep)}\n---\n')),
      'depth-over16');
  checks++;
  final d = FormulaProtocolCodec.decode(raw);
  final altered = d.toJson();
  altered['rows'][0][0] = 'changed';
  check(d.rows[0][0] == '[[RS87654321-Q5]]', 'toJson-does-not-alias');
  checks++;
  if (args.isNotEmpty) {
    final cross = jsonDecode(File(args.first).readAsStringSync()) as List;
    for (final c in cross) {
      final bytes = base64Decode(c['rawBase64']);
      if (c['accepted'] == true) {
        check(
            base64Encode(FormulaProtocolCodec.encode(
                    FormulaProtocolCodec.decode(bytes))) ==
                c['rawBase64'],
            'python-cross-${c['name']}');
      } else {
        rejects(() => FormulaProtocolCodec.decode(bytes),
            'python-cross-${c['name']}');
      }
      checks++;
    }
  }
  stdout.writeln(
      'PASS standalone Dart extended caps/immutable/cross-language: $checks checks');
}

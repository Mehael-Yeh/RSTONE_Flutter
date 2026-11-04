import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/models/formula_document.dart';
import 'package:rst_flutter/utils/formula_protocol_codec.dart';
import 'package:rst_flutter/utils/formula_association.dart';
import 'package:rst_flutter/data_sync/services/index_manager.dart';

Map<String, dynamic> specimen() =>
    jsonDecode(File('test/fixtures/recipe_protocol/valid.model.json')
        .readAsStringSync()) as Map<String, dynamic>;
String document([Map<String, dynamic>? m]) => utf8.decode(
    FormulaProtocolCodec.encode(FormulaDocument.fromJson(m ?? specimen())));

void main() {
  test(
      'structured personal path keeps its recipe namespace and exact stem even when name contains namespace text or .md',
      () {
    final m = specimen()..['title'] = '我的产品列表.md配方';
    final item =
        ProductItem.fromMdContent('user/产品配方/我的产品列表.md配方.md', document(m));
    expect(item.folder, '产品配方');
    expect(item.fileName, m['title']);
    expect(item.formulaDocument, isNotNull);
  });
  test(
      'quantitative owner gate compares original decimal strings exactly, not double underflow/overflow',
      () {
    for (final amount in ['0.${'0' * 400}1', '9' * 400]) {
      final m = specimen();
      m['rows'][0][1] = amount;
      expect(
          parseOfficialFiles({
            '产品列表/RS87654321-Q5.md': 'product',
            '产品配方/RS87654321-Q5-底.md': document(m)
          }).formulas,
          hasLength(1));
    }
    final reversed = specimen();
    reversed['rows'][0][1] = '9-${'0' * 400}1';
    expect(
        () => parseOfficialFiles({
              '产品列表/RS87654321-Q5.md': 'product',
              '产品配方/RS87654321-Q5-底.md': document(reversed)
            }),
        throwsFormatException);
  });
  test(
      'malformed header errors expose categories, not recipe JSON or cell values',
      () {
    const raw = '---\n{"title":"SYNTH_PRIVATE_VALUE","schema":BROKEN}\n---\n';
    try {
      FormulaProtocolCodec.decode(utf8.encode(raw));
      fail('must reject');
    } on FormatException catch (e) {
      expect(e.toString().contains('SYNTH_PRIVATE_VALUE'), isFalse);
    }
    try {
      FormulaProtocolCodec.decode(utf8.encode(
          document().replaceFirst('rstone-recipe/1', 'rstone-recipe/99')));
      fail('must reject');
    } on FormatException catch (e) {
      expect(e.message, contains('unsupported'));
    }
  });
  test(
      'structured owner path accepts adjudicated use labels without trimming a full grade suffix',
      () {
    for (final tail in ['处理剂', '白', '红', '涂料', '蓝', '面漆']) {
      final m = specimen()..['title'] = 'RS87654321-Q5-$tail';
      expect(
          parseOfficialFiles({
            '产品列表/RS87654321-Q5.md': 'product',
            '产品配方/RS87654321-Q5-$tail.md': document(m)
          }).formulas,
          hasLength(1));
    }
  });
  test(
      'official complete catalog rejects unresolved full grade, duplicate recipeId, title and nonpositive main',
      () {
    final m = specimen();
    final files = {
      '产品列表/RS87654321-Q5.md': 'product',
      '产品配方/RS87654321-Q5-底.md': document(m)
    };
    expect(
        parseOfficialFiles(files).formulas.single.formulaDocument, isNotNull);
    expect(() => parseOfficialFiles({'产品配方/RS87654321-Q5-底.md': document(m)}),
        throwsFormatException);
    expect(() => parseOfficialFiles({...files, '产品配方/other.md': document(m)}),
        throwsFormatException);
    final missing = specimen()
      ..['associatedProducts'] = ['RS87654321-Q5', 'RS87654321'];
    expect(
        () => parseOfficialFiles(
            {...files, '产品配方/RS87654321-Q5-底.md': document(missing)}),
        throwsFormatException);
    for (final amount in ['0', '适量', '0-1']) {
      final zero = specimen();
      zero['rows'][0][1] = amount;
      expect(
          () => parseOfficialFiles(
              {...files, '产品配方/RS87654321-Q5-底.md': document(zero)}),
          throwsFormatException);
    }
    final truncated = specimen()
      ..['ownerProduct'] = 'RS87654321'
      ..['associatedProducts'] = ['RS87654321'];
    expect(
        () => parseOfficialFiles({
              ...files,
              '产品列表/RS87654321.md': 'product',
              '产品配方/RS87654321-Q5-底.md': document(truncated)
            }),
        throwsFormatException);
  });
  test(
      'typed associations use all exact declared grades only, never title, prose or alias',
      () {
    final owner = ProductItem.fromMdContent('产品列表/RS87654321-Q5.md', '');
    final extra = ProductItem.fromMdContent('产品列表/RS222-X.md', '');
    final unrelated = ProductItem.fromMdContent('产品列表/RS333.md', '');
    final m = specimen()..['associatedProducts'] = ['RS87654321-Q5', 'RS222-X'];
    m['content'].add({'kind': 'note', 'text': '[[RS333]]'});
    final f = ProductItem.fromMdContent('产品配方/RS87654321-Q5-底.md', document(m));
    final all = [owner, extra, unrelated];
    expect(linkedFormulasForProduct(extra, [f], productCatalog: all), [f]);
    expect(
        linkedFormulasForProduct(unrelated, [f], productCatalog: all), isEmpty);
    final base = ProductItem.fromMdContent('产品列表/RS87654321.md', '');
    expect(linkedFormulasForProduct(base, [f], productCatalog: [...all, base]),
        isEmpty);
  });
  test(
      'ProductItem consumes immutable typed model, preserving original wiki + all five cells',
      () {
    final raw = document();
    final dynamic item =
        ProductItem.fromMdContent('产品配方/RS87654321-Q5-底.md', raw);
    final FormulaDocument d = item.formulaDocument;
    expect(d.rows, specimen()['rows']);
    expect(d.content[1], isA<FormulaProcess>());
    expect(() => d.rows[0][4] = 'changed', throwsUnsupportedError);
    expect(() => d.associatedProducts.add('changed'), throwsUnsupportedError);
    expect(() => (d.content[1] as FormulaProcess).steps.add('changed'),
        throwsUnsupportedError);
    expect(item.rawContent, raw);
    expect(item.frontmatter['schema'], 'rstone-recipe/1');
  });
  test(
      'new marker invalid, unknown, CRLF, BOM or body mismatch cannot downgrade to legacy',
      () {
    final raw = document();
    for (final bad in [
      raw.replaceFirst('rstone-recipe/1', 'rstone-recipe/99'),
      raw.replaceFirst('"schema":"rstone-recipe/1"', '"schema":null'),
      raw.replaceAll('\n', '\r\n'),
      '\uFEFF$raw',
      '$raw\n',
      '---\nschema: null\n---\n| old | 1 |',
      '---\n"schema": null\n---\n| old | 1 |',
      '---\n{"schema": broken\n---\n| old | 1 |'
    ]) {
      expect(() => ProductItem.fromMdContent('产品配方/bad.md', bad),
          throwsFormatException);
    }
  });
  test('legacy personal and product scalar parsing remains unchanged', () {
    final dynamic legacy = ProductItem.fromMdContent(
        'user/产品配方/old.md', '| 原料 | 量 |\n| -- | -- |\n| water | 1 |');
    expect(legacy.formulaDocument, isNull);
    final oldJson = ProductItem.fromMdContent(
        'user/产品配方/old-json.md', '---\n{"tags":["legacy"]}\n---\n| old | 1 |');
    expect(oldJson.formulaDocument, isNull);
    expect(oldJson.rawContent, contains('legacy'));
    final p = ProductItem.fromMdContent(
        '产品列表/RS1.md', '---\ntags:\n - 水性\n固含: 50%\n---\n性能');
    expect(p.solidContent, '50%');
    expect(p.tags, ['水性']);
    expect(p.frontmatter, isEmpty);
  });
}

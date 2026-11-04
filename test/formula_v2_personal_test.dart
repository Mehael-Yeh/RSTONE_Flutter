import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/formula_document.dart';
import 'formula_structured_test.dart' show specimen, document;
import 'support/sync_fixture.dart';

void main() {
  test('existing storage guard rejects ZIP traversal before any personal load',
      () async {
    final f = SignedFixture();
    await f.initialize();
    final s = await f.memoryStorage();
    await expectLater(
        () => s.writeText('user/产品配方/../../unsafe.md', 'untrusted'),
        throwsArgumentError);
    final app = await f.app(s);
    expect(await app.exportMarkdownArchive(), isNull);
    app.dispose();
    await s.close();
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'new personal save uses codec and full references, reload + personal ZIP preserve bytes',
      () async {
    final f = SignedFixture();
    await f.initialize();
    final s = await f.memoryStorage();
    final app = await f.app(s);
    await f.publish(1, {'产品列表/RS87654321-Q5.md': product('水性')});
    expect(await app.sync!.synchronize(), isTrue);
    final model =
        FormulaDocument.fromJson((specimen()..['schema'] = 'rstone-recipe/2'));
    final dynamic api = app;
    await api.addFormulaDocument(model);
    final path = 'user/产品配方/${model.title}.md';
    expect(await s.readText(path),
        document(specimen()..['schema'] = 'rstone-recipe/2'));
    expect(app.formulas.single.formulaDocument!.toJson(), model.toJson());
    final reopened = await f.app(s);
    expect(reopened.formulas.single.formulaDocument!.rows, model.rows);
    final zip =
        ZipDecoder().decodeBytes((await reopened.exportMarkdownArchive())!);
    expect(zip.files, hasLength(1));
    expect(zip.files.single.name, '产品配方/${model.title}.md');
    expect(utf8.decode(zip.files.single.content as List<int>),
        document(specimen()..['schema'] = 'rstone-recipe/2'));
    final bad = (specimen()..['schema'] = 'rstone-recipe/2')
      ..['associatedProducts'] = ['RS87654321-Q5', 'RS404'];
    await expectLater(
        () => api.addFormulaDocument(FormulaDocument.fromJson(bad)),
        throwsFormatException);
    expect(await s.readText(path),
        document(specimen()..['schema'] = 'rstone-recipe/2'));
    await expectLater(
        () =>
            app.addFormulaMarkdown(name: 'legacy new', markdown: '| old | 1 |'),
        throwsFormatException);
    reopened.dispose();
    app.dispose();
    await s.close();
  });
  test(
      'bad personal structured file isolated with original ZIP; does not block official initialization or reveal same-name official',
      () async {
    final f = SignedFixture();
    await f.initialize();
    final s = await f.memoryStorage();
    final app = await f.app(s);
    await f.publish(1, {
      '产品列表/RS87654321-Q5.md': product('水性'),
      '产品配方/RS87654321-Q5-底.md':
          document(specimen()..['schema'] = 'rstone-recipe/2')
    });
    expect(await app.sync!.synchronize(), isTrue);
    final bad = document(specimen()..['schema'] = 'rstone-recipe/2')
        .replaceFirst('rstone-recipe/2', 'rstone-recipe/9');
    const path = 'user/产品配方/RS87654321-Q5-底.md';
    await s.writeText(path, bad);
    await s.writeText('user/产品配方/old personal.md', '| old | 1 |');
    final reopened = await f.app(s);
    final dynamic api = reopened;
    expect(reopened.initializationError, isNull);
    expect(reopened.products, hasLength(1));
    expect(reopened.sync!.snapshot.formulas, hasLength(1));
    expect(reopened.formulas.map((f) => f.fileName), ['old personal']);
    expect(api.quarantinedFormulas.keys, contains('产品配方/RS87654321-Q5-底.md'));
    expect(reopened.logs.any((l) => l.contains('隔离')), isTrue);
    expect(await s.readText(path), bad);
    final zip =
        ZipDecoder().decodeBytes((await reopened.exportMarkdownArchive())!);
    expect(
        utf8.decode(
            zip.findFile('产品配方/RS87654321-Q5-底.md')!.content as List<int>),
        bad);
    expect(await reopened.sync!.synchronize(), isTrue);
    expect(reopened.formulas.map((f) => f.fileName), ['old personal']);
    final removed = await reopened.clearAllManualMarkdownData();
    expect(removed, 2);
    expect(await s.read(path), isNull);
    expect((reopened as dynamic).quarantinedFormulas, isEmpty);
    reopened.dispose();
    app.dispose();
    await s.close();
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rst_flutter/models/formula_document.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'formula_structured_test.dart' show specimen;
import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('dependent personal recipe cannot disappear after attempted product rename', () async {
    final fixture = SignedFixture(); await fixture.initialize();
    final storage = await fixture.memoryStorage(); final app = await fixture.app(storage);
    const old = 'RS87654321-Q5';
    await app.addProductMarkdown(code: old, markdown: 'personal product bytes');
    final model = FormulaDocument.fromJson(specimen()..['schema'] = 'rstone-recipe/2');
    final dynamic api = app; await api.addFormulaDocument(model);
    final prefs = PreferencesService(); await prefs.initialize();
    await prefs.saveProductNote(old, 'synthetic dependent annotation');
    final before = <String, List<int>>{};
    for (final key in await storage.keys('user/')) { before[key] = (await storage.read(key))!.toList(); }
    expect(app.formulas.map((f) => f.fileName), contains(model.title));
    Object? failure;
    try { await app.updateProductMarkdown(item: app.products.single, code: 'Renamed', markdown: 'edited'); }
    catch (error) { failure = error; }
    expect(app.formulas.map((f) => f.fileName), contains(model.title), reason: 'existing personal recipe remains visible');
    expect(failure, isA<StateError>(), reason: 'unsafe dependency rename must refuse before writes');
    final after = <String, List<int>>{};
    for (final key in await storage.keys('user/')) { after[key] = (await storage.read(key))!.toList(); }
    expect(after, before);
    expect(prefs.getProductNote(old), 'synthetic dependent annotation');
    expect(prefs.getProductNote('Renamed'), isEmpty);
    final reopened = await fixture.app(storage);
    expect(reopened.formulas.map((f) => f.fileName), contains(model.title));
    reopened.dispose(); app.dispose(); await storage.close();
  });
}

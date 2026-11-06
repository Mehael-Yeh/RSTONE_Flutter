// Synthetic regression: a name-only draft must not make a reference look resolvable.
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/services/obsidian_data_service.dart';
import 'support/sync_fixture.dart';

void main() {
  test('name-only draft does not silence a missing application reference',
      () async {
    final f = SignedFixture();
    await f.initialize();
    final s = await f.memoryStorage();
    final app = await f.app(s);
    const missing = 'RS87654321-银';
    await app.addApplicationMarkdown(
        name: 'SyntheticApp910001',
        markdown: '---\ntags:\n  - Synthetic\n底漆: "[[$missing]]"\n---\n');
    List<String> missingOf(ObsidianDataService service) {
      final out = <String>[];
      for (final item in service.applications) {
        out.addAll(service.unresolvedReferencesFor(item));
      }
      return out;
    }
    expect(missingOf(app), contains(missing));
    await app.addFormulaDraft(missing);
    final drafts = app.formulas.where((x) => x.isFormulaDraft);
    expect(drafts.map((x) => x.fileName), contains(missing));
    expect(missingOf(app), contains(missing),
        reason: 'a pending draft is not a usable recipe');
    final reopened = await f.app(s);
    expect(missingOf(reopened), contains(missing));
    reopened.dispose();
    app.dispose();
    await s.close();
  });
}

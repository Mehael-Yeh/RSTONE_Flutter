import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rst_flutter/main.dart';
import 'package:rst_flutter/services/obsidian_data_service.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'package:rst_flutter/utils/app_shapes.dart';
import 'package:rst_flutter/widgets/formula_editor_dialog.dart';
import 'package:rst_flutter/widgets/note_swipe_tile.dart';

void rounded(ShapeBorder? shape, String name) {
  expect(shape, isA<RoundedRectangleBorder>(), reason: name);
  expect((shape! as RoundedRectangleBorder).borderRadius,
      AppShapes.borderRadius, reason: name);
}

void main() {
  testWidgets('legacy dropdown menus and swipe actions share geometry', (tester) async {
    final data = ObsidianDataService();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: FormulaEditorDialog(dataService: data))));
    // The complete-form fields (including the legacy dropdown) live in an
    // optional section; expand it so the real widget is built and checked.
    await tester.tap(find.text('填写完整配方（可选）'));
    await tester.pumpAndSettle();
    final dropdown = tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>));
    expect(dropdown.borderRadius, AppShapes.borderRadius);
    final tile = NoteSwipeTile(onNoteTap: () async {}, child: const SizedBox());
    expect(tile.noteButtonBorderRadius, AppShapes.borderRadius);
    expect(tile.deleteButtonBorderRadius, AppShapes.borderRadius);
    await tester.pumpWidget(const SizedBox.shrink());
    data.dispose();
  });
  test('all lib corner declarations use the shared geometry', () {
    final violations = <String>[];
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') || file.path.endsWith('app_shapes.dart')) continue;
      final source = file.readAsStringSync();
      if (RegExp(r'(BorderRadius|Radius)\.(circular|all|vertical|horizontal)\(').hasMatch(source)) {
        violations.add(file.path.replaceAll('\\', '/'));
      }
    }
    expect(violations, isEmpty);
  });
  for (final brightness in Brightness.values) {
    testWidgets('actual root theme renders uniform Material surfaces $brightness', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = PreferencesService();
      await prefs.initialize();
      final data = ObsidianDataService();
      await tester.pumpWidget(RstoneApp(dataService: data, preferencesService: prefs));
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      final theme = brightness == Brightness.light ? app.theme! : app.darkTheme!;
      rounded(theme.cardTheme.shape, 'card');
      rounded(theme.dialogTheme.shape, 'dialog');
      rounded(theme.chipTheme.shape, 'chip');
      rounded(theme.popupMenuTheme.shape, 'popup');
      rounded(theme.bottomSheetTheme.shape, 'sheet');
      rounded(theme.snackBarTheme.shape, 'snackbar');
      rounded(theme.navigationBarTheme.indicatorShape, 'navigation');
      rounded(theme.filledButtonTheme.style!.shape!.resolve({}), 'filled');
      rounded(theme.textButtonTheme.style!.shape!.resolve({}), 'text');
      rounded(theme.outlinedButtonTheme.style!.shape!.resolve({}), 'outlined');
      rounded(theme.elevatedButtonTheme.style!.shape!.resolve({}), 'elevated');
      expect((theme.inputDecorationTheme.border! as OutlineInputBorder).borderRadius, AppShapes.borderRadius);
      await tester.pumpWidget(MaterialApp(theme: theme, home: Scaffold(body: SingleChildScrollView(child: Column(children: [
        const Card(child: SizedBox(width: 100, height: 30)),
        const Chip(label: Text('Synthetic tag')),
        const TextField(decoration: InputDecoration(labelText: 'Synthetic input')),
        FilledButton(onPressed: () {}, child: const Text('Synthetic action')),
        TextButton(onPressed: () {}, child: const Text('Synthetic text action')),
        const AlertDialog(title: Text('Synthetic dialog'), content: Text('Synthetic content')),
        PopupMenuButton<String>(itemBuilder: (_) => [const PopupMenuItem(value: 'test', child: Text('Synthetic menu'))]),
      ])))));
      await tester.pumpAndSettle();
      final chipMaterial = find.descendant(of: find.byType(Chip), matching: find.byType(Material)).first;
      rounded(tester.widget<Material>(chipMaterial).shape, 'rendered chip');
      final cardMaterial = find.descendant(of: find.byType(Card), matching: find.byType(Material)).first;
      rounded(tester.widget<Material>(cardMaterial).shape, 'rendered card');
      final dialogMaterial = find.descendant(of: find.byType(Dialog), matching: find.byType(Material)).first;
      rounded(tester.widget<Material>(dialogMaterial).shape, 'rendered dialog');
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      final popupMaterial = find.ancestor(of: find.text('Synthetic menu'), matching: find.byType(Material)).first;
      rounded(tester.widget<Material>(popupMaterial).shape, 'rendered popup');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      data.dispose();
    });
  }
}

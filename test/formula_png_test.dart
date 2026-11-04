import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/formula_document.dart';
import 'package:rst_flutter/widgets/product_detail/formula_presentation.dart';
import 'package:rst_flutter/widgets/product_detail/formula_png_renderer.dart';
import 'formula_structured_test.dart' show specimen;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'real PNG renders every raw cell, multiline and all ordered narratives from the display view',
      () async {
    final loader = FontLoader('sans-serif')
      ..addFont(rootBundle.load('assets/fonts/MicrosoftYaHei.ttf'));
    await loader.load();
    final m = specimen();
    m['rows'][0][4] = '  a|b\n多行末格  ';
    m['content'].add({
      'kind': 'process',
      'label': '分支2',
      'steps': ['温度保持', '末条工艺']
    });
    final d = FormulaDocument.fromJson(m);
    final view = FormulaDisplayView(d);
    expect(view.cells.skip(1).toList(), d.rows);
    final png = await FormulaPngRenderer.render(view);
    final codec = await ui.instantiateImageCodec(png);
    final image = (await codec.getNextFrame()).image;
    expect(image.width, greaterThan(800));
    expect(image.height, greaterThan(300));
    expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    if (Platform.environment['RECIPE_TEST_OUT'] case final String out) {
      File('$out/synthetic_recipe.png').writeAsBytesSync(png);
    }
    image.dispose();
    codec.dispose();
  });
}

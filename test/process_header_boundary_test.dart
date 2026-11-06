import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/formula_document.dart';
import 'package:rst_flutter/widgets/product_detail/formula_presentation.dart';
import 'package:rst_flutter/widgets/product_detail/formula_png_renderer.dart';
import 'package:rst_flutter/widgets/product_detail/structured_formula_card.dart';
import 'package:rst_flutter/widgets/product_detail/process_presentation.dart';
import 'formula_display_contract_test.dart' show synthetic;
void main(){
 for(final schema in ['rstone-recipe/1','rstone-recipe/2']){
 testWidgets('$schema parallel instructions never become table headings',(tester) async {
 const steps=['混合  搅拌','加热  80℃','保温  2小时'];
 expect(presentFormulaProcess(steps),steps);
 final raw=synthetic(length:1).toJson()..['schema']=schema;raw['content']=[{'kind':'process','label':'工艺900000','steps':steps}];final d=FormulaDocument.fromJson(raw);
 await tester.pumpWidget(MaterialApp(home:Scaffold(body:StructuredFormulaCard(document:d))));await tester.pumpAndSettle();
 for(final s in steps){expect(find.text(s),findsOneWidget);}
 final text=FormulaPngRenderer.layout(FormulaDisplayView(d)).text.map((n)=>n.text).toList();for(final s in steps){expect(text,contains(s));}expect(text.any((s)=>s.contains('混合：加热')),isFalse);expect(d.toJson(),raw);expect(tester.takeException(),isNull);
 });}
 test('unrecognized four-column and reordered headings are preserved',(){
 for(final steps in [
 ['混合  搅拌  加热  保温','液体  慢速  80℃  2小时','粉末  高速  50℃  1小时'],
 ['能量  波段  工段  说明','600  UVV  灯900001  内容','150  UVC  灯900002  内容'],
 ['固化段类型  波段标识  推荐能量密度  未知字段','LED900001  UVV  600  信息','LED900002  UVC  150  信息']]){expect(presentFormulaProcess(steps),steps);}
 });
}

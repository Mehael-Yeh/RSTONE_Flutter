import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaml/yaml.dart';
import 'package:rst_flutter/pages/product_list_page.dart';
import 'package:rst_flutter/services/preferences_service.dart';
import 'support/sync_fixture.dart';

void main() {
 test('new personal product scalars are YAML-safe literal strings', () async {
  final f=SignedFixture();await f.initialize();final s=await f.memoryStorage();final app=await f.app(s);
  for(final value in ['A: B','#literal','[literal]','{x: y}','*literal','true','001',r'quote " and \ slash','line1\nline2']) {
   final text=app.buildProductMarkdownTemplate(tags:['custom'],engineer:value,experimentalCode:value,solidContent:value,hydroxylValue:value,functionality:value,hardness:value,gloss60:value,boilResistance:value,waterContactAngle:value,technologySource:value,benchmark:value,viscosity:value);
   final front=RegExp(r'^---\n([\s\S]*?)\n---').firstMatch(text)!.group(1)!;
   expect(()=>loadYaml(front),returnsNormally,reason:'add form must quote $value');
   final m=loadYaml(front) as YamlMap;
   for(final key in ['工程师','实验牌号','固含','羟值','官能度','硬度','光泽(60°)','水煮','水接触角','技术源','对标','粘度']) {
    expect(m[key],value,reason:'$key must remain a literal string');
   }
  }
 });
 testWidgets('legacy unquoted colon scalar can be repaired by personal edit', (tester) async {
  tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});final prefs=PreferencesService();await tester.runAsync(prefs.initialize);
  final setup=await tester.runAsync(() async {final f=SignedFixture();await f.initialize();final s=await f.memoryStorage();final app=await f.app(s);await app.addProductMarkdown(code:'自定义修复',markdown:'---\ntags:\n  - custom\n工程师: A: B\n额外字段: custom: text\n未知结构:\n  子项: 保留\n---\n原正文保留');return (s,app);});
  final (s,app)=setup!;
  expect(app.products.single.engineer,'A: B');
  await tester.pumpWidget(MaterialApp(home:ProductListPage(dataService:app,preferencesService:prefs)));await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('编辑产品信息'));await tester.pumpAndSettle();
  final engineer=find.byType(TextField).at(2);expect(tester.widget<TextField>(engineer).controller!.text,'A: B');
  await tester.ensureVisible(engineer);await tester.enterText(engineer,'repaired: value # literal');
  await tester.tap(find.text('保存'));await tester.pumpAndSettle();
  expect(app.products.single.engineer,'repaired: value # literal');
  final saved=await tester.runAsync(()=>s.readText('user/产品列表/自定义修复.md'));
  expect(saved,contains('原正文保留'));
  final front=RegExp(r'^---\n([\s\S]*?)\n---').firstMatch(saved!)!.group(1)!;
  final m=loadYaml(front) as YamlMap;
  expect(m['额外字段'],'custom: text');expect(m['未知结构']['子项'],'保留');
  expect(tester.takeException(),isNull);
 });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:rst_flutter/models/product_item.dart';
import 'package:rst_flutter/widgets/product_detail/application_formula_links.dart';

void main() {
  test('personal application explicitly references an existing official recipe',
      () {
    final recipe = ProductItem.fromMdContent(
        '产品配方/RS900997-银.md', '---\ntags: []\n---\n',
        origin: DataOrigin.official);
    final app = ProductItem.fromMdContent('user/产品应用/我的合成应用.md',
        '---\ntags: []\n底漆: "[[产品配方/RS900997-银]]"\n---\n',
        origin: DataOrigin.user);
    expect(app.primer, '产品配方/RS900997-银');
    expect(resolveApplicationFormula(app, [recipe], app.primer!), same(recipe),
        reason: '用户明确填写的应用层位引用，不是个人同名产品自动继承官方配方');
  });
}

/// Immutable facts for rstone-recipe/1. No Markdown interpretation or approval.
final class FormulaDocument {
  static const schema = 'rstone-recipe/1';
  static const schemaV2 = 'rstone-recipe/2';
  static bool supportsSchema(dynamic value) =>
      value == schema || value == schemaV2;
  final String schemaVersion;
  static const maxItems = 1000, maxUtf16 = 4096;
  final String recipeId, title, classification, ownerProduct;
  final List<String> associatedProducts, columns, preTable;
  final List<List<String>> rows;
  final List<FormulaBlock> content;

  FormulaDocument._(
      this.schemaVersion,
      this.recipeId,
      this.title,
      this.classification,
      this.ownerProduct,
      this.associatedProducts,
      this.columns,
      this.rows,
      this.preTable,
      this.content);

  factory FormulaDocument.fromJson(dynamic value) {
    _keys(value, const {
      'schema',
      'recipeId',
      'title',
      'classification',
      'ownerProduct',
      'associatedProducts',
      'columns',
      'rows',
      'preTable',
      'content'
    });
    final m = value as Map;
    _require(supportsSchema(m['schema']));
    final id = _text(m['recipeId'], nonempty: true);
    _require(RegExp(r'^[A-Za-z0-9._-]{1,128}$').hasMatch(id));
    final title = _text(m['title'], nonempty: true);
    final role = _text(m['classification'], nonempty: true);
    _require(
        const {'main', 'example', 'reference', 'unverified'}.contains(role));
    final owner = _text(m['ownerProduct'], nonempty: true);
    final refs = _texts(m['associatedProducts'], nonempty: true);
    _require(refs.every((r) => r.isNotEmpty) &&
        refs.toSet().length == refs.length &&
        refs.contains(owner));
    final columns = _texts(m['columns']);
    _require(columns.length == 5 &&
        columns[0] == '原料编号' &&
        (columns[1] == '投入数' || columns[1] == '投入数(g)') &&
        columns[2] == '百分比(%)' &&
        columns[3] == '供应商' &&
        columns[4] == '备注');
    final rows = <List<String>>[];
    for (final r in _list(m['rows'], nonempty: true)) {
      final row = _texts(r);
      _require(row.length == 5 && row[0].isNotEmpty && row[1].isNotEmpty);
      rows.add(row);
    }
    final pre = _texts(m['preTable']);
    final blocks = <FormulaBlock>[];
    for (final b in _list(m['content'])) {
      _require(b is Map);
      if (b['kind'] == 'note') {
        _keys(b, const {'kind', 'text'});
        blocks.add(FormulaNote(_text(b['text'])));
      } else if (b['kind'] == 'process') {
        _keys(b, const {'kind', 'label', 'steps'});
        blocks.add(FormulaProcess(_text(b['label'], nonempty: true),
            _texts(b['steps'], nonempty: true)));
      } else {
        _require(false);
      }
    }
    return FormulaDocument._(m['schema'] as String, id, title, role, owner,
        refs, columns, List.unmodifiable(rows), pre, List.unmodifiable(blocks));
  }

  Map<String, dynamic> toJson() => {
        'schema': schemaVersion,
        'recipeId': recipeId,
        'title': title,
        'classification': classification,
        'ownerProduct': ownerProduct,
        'associatedProducts': associatedProducts.toList(),
        'columns': columns.toList(),
        'rows': rows.map((r) => r.toList()).toList(),
        'preTable': preTable.toList(),
        'content': content.map((b) => b.toJson()).toList(),
      };
}

sealed class FormulaBlock {
  const FormulaBlock();
  Map<String, dynamic> toJson();
}

final class FormulaNote extends FormulaBlock {
  final String text;
  const FormulaNote(this.text);
  @override
  Map<String, dynamic> toJson() => {'kind': 'note', 'text': text};
}

final class FormulaProcess extends FormulaBlock {
  final String label;
  final List<String> steps;
  FormulaProcess(this.label, List<String> steps)
      : steps = List.unmodifiable(steps);
  @override
  Map<String, dynamic> toJson() =>
      {'kind': 'process', 'label': label, 'steps': steps.toList()};
}

void _require(bool ok) {
  if (!ok) throw const FormatException('invalid-structured-recipe');
}

void _keys(dynamic m, Set<String> keys) => _require(
    m is Map && m.length == keys.length && m.keys.every(keys.contains));
String _text(dynamic s, {bool nonempty = false}) {
  _require(s is String);
  final text = s as String;
  _require(text.length <= FormulaDocument.maxUtf16 &&
      (!nonempty || text.isNotEmpty));
  for (var i = 0; i < text.length; i++) {
    final u = text.codeUnitAt(i);
    _require(u >= 32 || u == 9 || u == 10);
    if (u >= 0xd800 && u <= 0xdbff) {
      _require(++i < text.length);
      final low = text.codeUnitAt(i);
      _require(low >= 0xdc00 && low <= 0xdfff);
    } else {
      _require(u < 0xdc00 || u > 0xdfff);
    }
  }
  return text;
}

List<dynamic> _list(dynamic v, {bool nonempty = false}) {
  _require(v is List &&
      v.length <= FormulaDocument.maxItems &&
      (!nonempty || v.isNotEmpty));
  return v as List;
}

List<String> _texts(dynamic v, {bool nonempty = false}) =>
    List.unmodifiable(_list(v, nonempty: nonempty).map((s) => _text(s)));

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/formula_document.dart';
import '../data_sync/protocol/rstone_protocol.dart' show parseUniqueJson;
import '../services/obsidian_data_service.dart';
import '../utils/formula_table_clipboard_parser.dart';

/// New personal recipes always save the same closed model as official recipes.
/// Advanced narrative input is explicit ordered JSON, never inferred Markdown.
class FormulaEditorDialog extends StatefulWidget {
  final ObsidianDataService dataService;
  const FormulaEditorDialog({super.key, required this.dataService});
  @override
  State<FormulaEditorDialog> createState() => _FormulaEditorDialogState();
}

class _FormulaEditorDialogState extends State<FormulaEditorDialog> {
  final _title = TextEditingController(),
      _owner = TextEditingController(),
      _refs = TextEditingController();
  final _input = TextEditingController(text: '原料编号\t投入数(g)\t百分比(%)\t供应商\t备注\n');
  final _pre = TextEditingController(text: '[]'),
      _content = TextEditingController(text: '[]');
  late final String _recipeId;
  String _classification = 'unverified';
  String? _error;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    final random = Random.secure();
    // Generated once for this creation, not from mutable title/BOM or a clock.
    _recipeId =
        'personal-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  }

  @override
  void dispose() {
    for (final c in [_title, _owner, _refs, _input, _pre, _content]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    final result = FormulaTableClipboardParser.parse(text);
    if (!mounted) return;
    if (!result.isValid) {
      setState(() => _error = result.errorMessage);
      return;
    }
    _input.text = result.tsv;
    setState(() => _error = null);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final table = FormulaTableClipboardParser.parse(_input.text);
      if (!table.isValid) {
        setState(() => _error = table.errorMessage);
        return;
      }
      final d = FormulaDocument.fromJson({
        'schema': FormulaDocument.schema,
        'recipeId': _recipeId,
        'title': _title.text,
        'classification': _classification,
        'ownerProduct': _owner.text,
        'associatedProducts':
            _refs.text.split('\n').where((s) => s.isNotEmpty).toList(),
        'columns': table.columns,
        'rows': table.rows,
        'preTable': parseUniqueJson(Uint8List.fromList(utf8.encode(_pre.text))),
        'content':
            parseUniqueJson(Uint8List.fromList(utf8.encode(_content.text))),
      });
      await widget.dataService.addFormulaDocument(d);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '保存失败：请检查名称、完整型号引用、五列或有序JSON结构。原文未覆盖。');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String key, String label,
            {int lines = 1, String? hint}) =>
        Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
                key: ValueKey(key),
                controller: c,
                minLines: lines,
                maxLines: lines == 1 ? 1 : lines + 3,
                decoration: InputDecoration(
                    labelText: label,
                    hintText: hint,
                    border: const OutlineInputBorder())));
    return AlertDialog(
        title: const Text('新增产品配方'),
        content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              field(_title, 'recipe-title', '名称'),
              field(_owner, 'recipe-owner', '主产品完整型号'),
              field(_refs, 'recipe-associations', '关联产品（每行一个，须包含主产品）',
                  lines: 2),
              DropdownButtonFormField<String>(
                  value: _classification,
                  decoration: const InputDecoration(labelText: '性质（不代表批准）'),
                  items: const [
                    DropdownMenuItem(value: 'unverified', child: Text('未验证')),
                    DropdownMenuItem(value: 'main', child: Text('主方')),
                    DropdownMenuItem(value: 'example', child: Text('示例')),
                    DropdownMenuItem(value: 'reference', child: Text('参考'))
                  ],
                  onChanged: (s) => setState(() => _classification = s!)),
              const SizedBox(height: 12),
              field(_input, 'recipe-input', '五列表格（TSV或Markdown）',
                  lines: 5, hint: '原料编号、投入数、百分比、供应商、备注；不缺列，不截列'),
              OutlinedButton.icon(
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste),
                  label: const Text('从剪切板获取')),
              const SizedBox(height: 12),
              field(_pre, 'recipe-pre', '前置说明（JSON字符串数组，可选）', lines: 2),
              field(_content, 'recipe-content', '有序说明和工艺（JSON数组，可选）',
                  lines: 3,
                  hint:
                      '[{"kind":"note","text":"说明"},{"kind":"process","label":"工艺","steps":["条目"]}]'),
              if (_error != null)
                Text(_error!,
                    key: const ValueKey('recipe-error'),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
            ]))),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('取消')),
          FilledButton(
              key: const ValueKey('recipe-save'),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '保存中' : '保存'))
        ]);
  }
}

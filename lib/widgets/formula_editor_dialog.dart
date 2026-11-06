import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/formula_document.dart';
import '../models/product_item.dart';
import '../services/obsidian_data_service.dart';
import '../utils/formula_table_clipboard_parser.dart';
import '../utils/app_shapes.dart';

/// Name-only reminders are personal drafts, isolated from full recipe schemas.
class FormulaEditorDialog extends StatefulWidget {
  final ObsidianDataService dataService;
  final ProductItem? draft;
  const FormulaEditorDialog({super.key, required this.dataService, this.draft});
  @override
  State<FormulaEditorDialog> createState() => _FormulaEditorDialogState();
}

class _FormulaEditorDialogState extends State<FormulaEditorDialog> {
  final _title = TextEditingController(),
      _owner = TextEditingController(),
      _refs = TextEditingController();
  final _input =
      TextEditingController(text: '原料编号\t投入数(g)\t百分比(%)\t供应商\t备注\n');
  final _pre = TextEditingController(), _content = TextEditingController();
  late final String _recipeId;
  String _classification = 'unverified';
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title.text = widget.draft?.fileName ?? '';
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

  /// True only when the user supplied real recipe content in any optional field.
  bool get _hasDetails =>
      [_owner, _refs, _pre, _content].any((c) => c.text.trim().isNotEmpty) ||
      _classification != 'unverified' ||
      _input.text.trim() != '原料编号\t投入数(g)\t百分比(%)\t供应商\t备注';

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // Name-only saves a personal reminder. It never fabricates a BOM.
      if (!_hasDetails) {
        if (widget.draft == null) {
          await widget.dataService.addFormulaDraft(_title.text);
          if (mounted) Navigator.pop(context);
        } else {
          setState(() => _error = '还没有填写配方内容；保留待补充记录请点“取消”。');
        }
        return;
      }
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
        'associatedProducts': {
          _owner.text,
          ..._refs.text.split('\n').where((s) => s.isNotEmpty),
        }.toList(),
        'columns': table.columns,
        'rows': table.rows,
        'preTable': _pre.text
            .split('\n')
            .where((s) => s.trim().isNotEmpty)
            .toList(),
        'content': _content.text.trim().isEmpty
            ? []
            : [
                {
                  'kind': 'process',
                  'label': '操作步骤',
                  'steps': _content.text
                      .split('\n')
                      .where((s) => s.trim().isNotEmpty)
                      .toList()
                }
              ],
      });
      if (widget.draft != null) {
        final cleaned =
            await widget.dataService.completeFormulaDraft(widget.draft!, d);
        if (!cleaned && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:
                  Text('完整配方已保存，待补充记录暂未移除。请勿重复补充，可稍后移除待补充记录。')));
        }
      } else {
        await widget.dataService.addFormulaDocument(d);
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            '未保存，请检查名称是否重复或含特殊符号；填写完整配方时还需选择有效产品并提供真实原料表。原资料未覆盖。');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(TextEditingController c, String key, String label,
          {int lines = 1, String? hint, bool readOnly = false}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
              key: ValueKey(key),
              controller: c,
              readOnly: readOnly,
              minLines: lines,
              maxLines: lines == 1 ? 1 : lines + 3,
              decoration: InputDecoration(
                  labelText: label,
                  hintText: hint,
                  border: const OutlineInputBorder(
                      borderRadius: AppShapes.borderRadius))));

  List<Widget> _completeFields() => [
        _field(_owner, 'recipe-owner', '对应产品（完整型号）'),
        _field(_refs, 'recipe-associations', '其他用到的产品（可选，每行一个）',
            lines: 2),
        DropdownButtonFormField<String>(
            value: _classification,
            decoration: const InputDecoration(labelText: '性质（不代表批准）'),
            borderRadius: AppShapes.borderRadius,
            items: const [
              DropdownMenuItem(value: 'unverified', child: Text('未验证')),
              DropdownMenuItem(value: 'main', child: Text('主方')),
              DropdownMenuItem(value: 'example', child: Text('示例')),
              DropdownMenuItem(value: 'reference', child: Text('参考'))
            ],
            onChanged: (s) => setState(() => _classification = s!)),
        const SizedBox(height: 12),
        _field(_input, 'recipe-input', '原料表（从表格复制粘贴即可）',
            lines: 5,
            hint: '原料编号、投入数、百分比、供应商、备注；不缺列，不截列'),
        OutlinedButton.icon(
            onPressed: _paste,
            icon: const Icon(Icons.content_paste),
            label: const Text('从剪切板获取')),
        const SizedBox(height: 12),
        _field(_pre, 'recipe-pre', '配方说明（可选，每行一条）', lines: 2),
        _field(_content, 'recipe-content', '操作步骤（可选，每行一步）', lines: 3),
      ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
        title: Text(widget.draft == null ? '新增产品配方' : '补充配方'),
        content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              _field(_title, 'recipe-title', '名称',
                  readOnly: widget.draft != null),
              const Text('只填名称可保存为个人待补充配方，不含原料，也不代表可复现实方。'),
              ExpansionTile(
                  title: const Text('填写完整配方（可选）'),
                  children: _completeFields()),
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

import 'package:flutter/material.dart';
import '../models/product_item.dart';
import '../services/obsidian_data_service.dart';
import 'formula_editor_dialog.dart';

/// Drafts intentionally have no copy/share action: there is no real BOM yet.
class FormulaDraftListDialog extends StatelessWidget {
  final ObsidianDataService dataService;
  const FormulaDraftListDialog({super.key, required this.dataService});

  Future<void> _confirmRemove(BuildContext context, ProductItem draft) async {
    final remove = await showDialog<bool>(
        context: context,
        builder: (confirm) => AlertDialog(
              title: const Text('移除待补充记录'),
              content: Text('将移除“${draft.fileName}”这条个人待补充记录，其他资料不变。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(confirm, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(confirm, true),
                    child: const Text('移除')),
              ],
            ));
    if (remove != true) return;
    try {
      await dataService.deleteManualItem(draft);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('未能移除，请关闭后重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('待补充配方'),
        content: SizedBox(
            width: 600,
            child: ListenableBuilder(
              listenable: dataService,
              builder: (context, _) {
                final drafts =
                    dataService.formulas.where((p) => p.isFormulaDraft).toList();
                return SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('仅个人可见的待补充记录，尚无原料表，不能作为实方复制或分享。'),
                  if (drafts.isEmpty) const Text('暂无待补充配方'),
                  for (final draft in drafts)
                    ListTile(
                      title: Text(draft.fileName),
                      subtitle: const Text('待补充 · 个人'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        TextButton(
                            child: const Text('补充'),
                            onPressed: () => showDialog<void>(
                                context: context,
                                builder: (_) => FormulaEditorDialog(
                                    dataService: dataService, draft: draft))),
                        IconButton(
                            tooltip: '移除待补充记录',
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => _confirmRemove(context, draft)),
                      ]),
                    ),
                ]));
              },
            )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('关闭'))
        ],
      );
}

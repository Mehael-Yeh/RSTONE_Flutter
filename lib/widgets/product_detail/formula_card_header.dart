import 'package:flutter/material.dart';

/// Selection belongs to the page; only presentation is shared by both formats.
/// Keep action targets fixed while allowing even very long names to ellipsize.
class FormulaCardHeader extends StatelessWidget {
  final String title;
  final Widget? selector;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  const FormulaCardHeader(
      {super.key,
      required this.title,
      this.selector,
      required this.onCopy,
      required this.onShare});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 12, right: 4),
        child: Row(children: [
          if (selector != null)
            const Text('配方：',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          Expanded(
              child: selector ??
                  Text('配方：$title',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold))),
          SizedBox(
              width: 48,
              height: 48,
              child: IconButton(
                  tooltip: '复制配方五列',
                  icon: const Icon(Icons.copy),
                  onPressed: onCopy)),
          SizedBox(
              width: 48,
              height: 48,
              child: IconButton(
                  tooltip: '分享配方图片',
                  icon: const Icon(Icons.share_outlined),
                  onPressed: onShare)),
        ]),
      );
}

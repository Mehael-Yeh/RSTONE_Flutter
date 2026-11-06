import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

/// Fully expanded rows with a frozen first column during horizontal panning.
/// Vertical scrolling belongs only to the enclosing detail page; the header is
/// the first natural row, not a second sticky viewport.
class FormulaPinnedTable extends StatefulWidget {
  final String id;
  final List<double> widths, heights;
  final Widget Function(int row, int column) cell;
  const FormulaPinnedTable(
      {super.key,
      required this.id,
      required this.widths,
      required this.heights,
      required this.cell});
  @override
  State<FormulaPinnedTable> createState() => _FormulaPinnedTableState();
}

class _FormulaPinnedTableState extends State<FormulaPinnedTable> {
  final _horizontal = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.widths, h = widget.heights;
    final height = h.fold<double>(0, (a, b) => a + b);
    final remaining = w.skip(1).fold<double>(0, (a, b) => a + b);
    final behavior = ScrollConfiguration.of(context);
    return SizedBox(
        height: height,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: w.first,
              child: Column(children: [
                for (var r = 0; r < h.length; r++) widget.cell(r, 0),
              ])),
          Expanded(
              child: ScrollConfiguration(
                  // No explicit or inherited horizontal thumb. A desktop mouse
                  // can pan the content directly, without the removed scrollbar.
                  behavior: behavior.copyWith(
                    scrollbars: false,
                    dragDevices: {
                      ...behavior.dragDevices,
                      PointerDeviceKind.mouse
                    },
                  ),
                  child: SingleChildScrollView(
                      key: ValueKey('recipe-scroll:${widget.id}'),
                      controller: _horizontal,
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      child: SizedBox(
                          width: remaining,
                          height: height,
                          child: Column(children: [
                            for (var r = 0; r < h.length; r++)
                              Row(children: [
                                for (var c = 1; c < w.length; c++)
                                  widget.cell(r, c),
                              ]),
                          ]))))),
        ]));
  }
}

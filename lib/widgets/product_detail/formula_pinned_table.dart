import 'dart:math' as math;
import 'package:flutter/material.dart';

/// One horizontal viewport for header and body, plus synchronized vertical
/// viewports for the frozen first column and the remaining body columns.
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
  final _left = ScrollController();
  final _body = ScrollController();
  final _horizontal = ScrollController();
  bool _syncing = false;
  void _sync(ScrollController from, ScrollController to) {
    if (_syncing || !from.hasClients || !to.hasClients) return;
    _syncing = true;
    to.jumpTo(from.offset.clamp(0.0, to.position.maxScrollExtent));
    _syncing = false;
  }

  @override
  void initState() {
    super.initState();
    _left.addListener(() => _sync(_left, _body));
    _body.addListener(() => _sync(_body, _left));
  }

  @override
  void dispose() {
    _left.dispose();
    _body.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.widths, h = widget.heights;
    final total = h.fold<double>(0, (a, b) => a + b);
    // A bounded table viewport leaves the enclosing detail page scrollable.
    final cap = (MediaQuery.sizeOf(context).height * .45).clamp(160.0, 420.0);
    final height = math.min(total, cap);
    final remaining = w.skip(1).fold<double>(0, (a, b) => a + b);
    Widget tail(int row) => Row(children: [
          for (var c = 1; c < w.length; c++) widget.cell(row, c),
        ]);
    return SizedBox(
        height: height,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: w.first,
              child: Column(children: [
                widget.cell(0, 0),
                Expanded(
                    child: SingleChildScrollView(
                        key: ValueKey('recipe-vertical:${widget.id}'),
                        controller: _left,
                        primary: false,
                        physics: const ClampingScrollPhysics(),
                        child: Column(children: [
                          for (var r = 1; r < h.length; r++) widget.cell(r, 0)
                        ]))),
              ])),
          Expanded(
              child: Scrollbar(
                  controller: _horizontal,
                  thumbVisibility: true,
                  interactive: true,
                  scrollbarOrientation: ScrollbarOrientation.bottom,
                  notificationPredicate: (n) =>
                      n.metrics.axis == Axis.horizontal,
                  child: SingleChildScrollView(
                      key: ValueKey('recipe-scroll:${widget.id}'),
                      controller: _horizontal,
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      child: SizedBox(
                          width: remaining,
                          height: height,
                          child: Column(children: [
                            tail(0),
                            Expanded(
                                child: Scrollbar(
                                    controller: _body,
                                    notificationPredicate: (n) =>
                                        n.metrics.axis == Axis.vertical,
                                    child: SingleChildScrollView(
                                        controller: _body,
                                        primary: false,
                                        physics: const ClampingScrollPhysics(),
                                        child: Column(children: [
                                          for (var r = 1; r < h.length; r++)
                                            tail(r)
                                        ])))),
                          ]))))),
        ]));
  }
}

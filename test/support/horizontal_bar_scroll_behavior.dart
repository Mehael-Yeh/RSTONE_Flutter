import 'package:flutter/material.dart';

/// Stress the application boundary with a host that adds horizontal bars.
/// The formula viewport must opt out, independent of platform defaults.
class HorizontalBarScrollBehavior extends MaterialScrollBehavior {
  const HorizontalBarScrollBehavior();
  @override
  Widget buildScrollbar(
      BuildContext context, Widget child, ScrollableDetails details) {
    if (axisDirectionToAxis(details.direction) == Axis.horizontal) {
      return RawScrollbar(
          controller: details.controller, thumbVisibility: true, child: child);
    }
    return super.buildScrollbar(context, child, details);
  }
}

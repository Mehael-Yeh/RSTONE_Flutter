import 'package:flutter/material.dart';

/// One corner geometry for all non-circular app surfaces (tags, cards, inputs,
/// dialogs, menus and buttons). Eight logical pixels reads as clearly rounded
/// on the 22-pixel tag chips while staying inside every real content surface.
abstract final class AppShapes {
  static const double radius = 8;
  static const corner = Radius.circular(radius);
  static const borderRadius = BorderRadius.all(corner);
  static const rounded = RoundedRectangleBorder(borderRadius: borderRadius);
  static const top = BorderRadius.vertical(top: corner);
  /// Deliberate pill for the four-pixel bottom-sheet drag handle. A real pill
  /// is half its height; forcing the shared radius there would be silently
  /// clamped by Flutter and look different anyway.
  static const handlePill = BorderRadius.vertical(top: Radius.circular(2));
  static const left = BorderRadius.horizontal(left: corner);
  static const right = BorderRadius.horizontal(right: corner);
  static const input = OutlineInputBorder(borderRadius: borderRadius);
}

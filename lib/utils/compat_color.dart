import 'package:flutter/material.dart';

extension RstoneColorCompat on Color {
  Color withCompatOpacity(double opacity) {
    // ignore: deprecated_member_use
    return withOpacity(opacity);
  }

  int get compatArgb32 {
    // ignore: deprecated_member_use
    return value;
  }

  int get compatRed {
    // ignore: deprecated_member_use
    return red;
  }

  int get compatGreen {
    // ignore: deprecated_member_use
    return green;
  }

  int get compatBlue {
    // ignore: deprecated_member_use
    return blue;
  }
}

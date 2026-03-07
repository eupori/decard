import 'package:flutter/material.dart';

class Responsive {
  static const double tabletBreakpoint = 768;
  static const double contentMaxWidth = 640;

  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= tabletBreakpoint;
}

import 'package:flutter/material.dart';

import '../models/enums.dart';

/// Chart colors from a colorblind-checked categorical palette, with separate
/// steps for dark mode. Each entity keeps its color on every chart.
class ChartColors {
  ChartColors._(this._dark);

  factory ChartColors.of(BuildContext context) =>
      ChartColors._(Theme.of(context).brightness == Brightness.dark);

  final bool _dark;

  static const _light = [
    Color(0xFF2A78D6), // blue
    Color(0xFFEB6834), // orange
    Color(0xFF1BAF7A), // aqua
    Color(0xFFEDA100), // yellow
    Color(0xFFE87BA4), // magenta
    Color(0xFF008300), // green
    Color(0xFF6250D6), // violet
    Color(0xFFE34948), // red
  ];
  static const _darkSteps = [
    Color(0xFF3987E5),
    Color(0xFFD95926),
    Color(0xFF199E70),
    Color(0xFFC98500),
    Color(0xFFD55181),
    Color(0xFF008300),
    Color(0xFF9085E9),
    Color(0xFFE66767),
  ];

  /// Categorical slot, in fixed order. Slots past 8 should be folded into
  /// "Other" by the caller.
  Color slot(int i) => (_dark ? _darkSteps : _light)[i % 8];

  Color get other => _dark ? const Color(0xFF6E6D68) : const Color(0xFFA3A29C);

  Color get income => slot(0);
  Color get expense => slot(1);

  Color bucket(Bucket b) => switch (b) {
        Bucket.needs => slot(2),
        Bucket.wants => slot(3),
        Bucket.savings => slot(4),
      };
}

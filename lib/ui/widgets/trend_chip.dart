import 'package:flutter/material.dart';

/// A change against an earlier month, period or year: an up or down arrow
/// and the size of the change. Green when the change is good, red when bad
/// (more spending is bad), grey when it is too small to matter.
class TrendChip extends StatelessWidget {
  const TrendChip({super.key, required this.value, this.suffix = '%', this.upIsGood = true, this.dense = false});

  /// Percent (or points, with [suffix] ' pts'), signed.
  final double value;
  final String suffix;
  final bool upIsGood;

  /// Smaller and without a background, for table cells.
  final bool dense;

  /// Changes below this are shown as flat.
  static const flat = 0.5;

  static Color colorFor(BuildContext context, double value, {bool upIsGood = true}) {
    if (value.abs() < flat) return Theme.of(context).colorScheme.onSurfaceVariant;
    return (value > 0) == upIsGood ? Colors.green.shade600 : Theme.of(context).colorScheme.error;
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(context, value, upIsGood: upIsGood);
    final icon = value.abs() < flat ? Icons.arrow_forward : (value > 0 ? Icons.arrow_upward : Icons.arrow_downward);
    final style = (dense ? Theme.of(context).textTheme.labelSmall : Theme.of(context).textTheme.labelMedium)
        ?.copyWith(color: color, fontWeight: FontWeight.w600);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: dense ? 12 : 14, color: color),
        const SizedBox(width: 2),
        Text('${value.abs().toStringAsFixed(1)}$suffix', style: style),
      ],
    );
    if (dense) return content;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
      child: content,
    );
  }
}

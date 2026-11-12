import 'package:flutter/material.dart';

import 'glass.dart';

/// The design's segmented control: a glass pill with a filled selected part.
class SegmentedPill extends StatelessWidget {
  const SegmentedPill({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassBox(
      blur: false,
      radius: 26,
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected ? cs.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: i == selected
                          ? cs.onPrimary
                          : cs.onSurface.withAlpha(170),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

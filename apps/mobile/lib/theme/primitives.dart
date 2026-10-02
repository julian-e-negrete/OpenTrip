import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Shared building blocks assembled once, per the design handoff's
/// suggested implementation order — every Nocturne screen is built out
/// of these six: [NoctPanel], [FadingRule], [NoctStat] (the stat column),
/// [NoctSegmentedControl], [NoctOutlinedButton], and [NoctTagChip].

/// A flat `surface` panel with a hairline `n800` edge — the standard
/// "resting" surface everywhere in Nocturne. Pass [accent] for the
/// "yours / live" tinted variant ([Noct.panelAccent]).
class NoctPanel extends StatelessWidget {
  const NoctPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(13),
    this.accent = false,
    this.borderRadius,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool accent;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final decoration = accent ? Noct.panelAccent : Noct.panel;
    final radius = borderRadius ?? BorderRadius.circular(Noct.rMd);
    final content = Container(
      decoration: decoration.copyWith(borderRadius: radius),
      padding: padding,
      child: child,
    );
    if (onTap == null) return content;
    return ClipRRect(
      borderRadius: radius,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          overlayColor: WidgetStatePropertyAll(Noct.accent.withValues(alpha: 0.05)),
          child: content,
        ),
      ),
    );
  }
}

/// The Nocturne signature: a 1px horizontal rule that fades in from
/// transparent, holds `n800` through the middle, and fades back out —
/// used on Trips, Record (numbers), and Recap.
class FadingRule extends StatelessWidget {
  const FadingRule({super.key, this.inset = 48});

  /// Distance, in logical pixels, over which the rule fades in/out at
  /// each end.
  final double inset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final stop = w <= 0 ? 0.5 : (inset / w).clamp(0.0, 0.5);
        return Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: const [Colors.transparent, Noct.n800, Noct.n800, Colors.transparent],
              stops: [0.0, stop, 1 - stop, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// A big tabular numeral over a small uppercase micro-label — the
/// "value + label" stat column used everywhere from the Trips summary
/// strip to the Record hero.
class NoctStat extends StatelessWidget {
  const NoctStat({
    super.key,
    required this.value,
    required this.label,
    this.suffix,
    this.valueSize = 23,
    this.valueColor,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.labelGap = 3,
  });

  final String value;
  final String label;
  final String? suffix;
  final double valueSize;
  final Color? valueColor;
  final CrossAxisAlignment crossAxisAlignment;
  final double labelGap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: value, style: Noct.stat(valueSize, color: valueColor)),
              if (suffix != null)
                TextSpan(
                  text: suffix,
                  style: const TextStyle(fontSize: 12, color: Noct.n500, fontWeight: FontWeight.w400),
                ),
            ],
          ),
        ),
        SizedBox(height: labelGap),
        Text(label.toUpperCase(), style: Noct.statLabel),
      ],
    );
  }
}

/// A small pill — the tag chip used on Trips route cards (`time`,
/// `ø 45 km/h`, `41° lean`) and similar contexts. Neutral by default;
/// [accent] gives the `a900`/`a200` tinted variant used for the one
/// standout tag in a row (e.g. lean angle).
class NoctTagChip extends StatelessWidget {
  const NoctTagChip(this.text, {super.key, this.accent = false});

  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent ? Noct.a900 : Noct.n900,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10.5, color: accent ? Noct.a200 : Noct.n300, fontWeight: FontWeight.w400),
      ),
    );
  }
}

/// A row of mutually-exclusive pill options — used for Global/Friends
/// scope switches, category rows, and Appearance's option chips.
/// Selected = `a900` fill / `a100` text / `a700` border; unselected =
/// transparent / `n400` text / `divider` border (or fully borderless
/// when [bordered] is false, for the segmented-control variant that
/// only draws its own outer border).
class NoctSegmentedControl<T> extends StatelessWidget {
  const NoctSegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.wrap = false,
  });

  final List<(T value, String label)> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// Chips wrap onto multiple lines (Appearance) instead of a single
  /// scrollable/fixed row (category rows, scope switches).
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final chips = [
      for (final option in options)
        _Chip(
          label: option.$2,
          selected: option.$1 == value,
          onTap: () => onChanged(option.$1),
        ),
    ];
    if (wrap) {
      return Wrap(spacing: 7, runSpacing: 7, children: chips);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [for (final c in chips) Padding(padding: const EdgeInsets.only(right: 7), child: c)],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Noct.rMd),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          overlayColor: WidgetStatePropertyAll(Noct.accent.withValues(alpha: 0.05)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? Noct.a900 : Colors.transparent,
              borderRadius: BorderRadius.circular(Noct.rMd),
              border: Border.all(color: selected ? Noct.a700 : Noct.divider),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? Noct.a100 : Noct.n400,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A full-width (or intrinsic-width) outlined action — 1.5px accent
/// border, `a200` label, optional leading glyph. The primary action
/// style throughout Nocturne; nothing is filled.
class NoctOutlinedButton extends StatelessWidget {
  const NoctOutlinedButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton(
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: Noct.a200),
            const SizedBox(width: 8),
          ],
          Text(label),
        ],
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

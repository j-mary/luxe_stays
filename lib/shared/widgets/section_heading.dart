import 'package:flutter/material.dart';

/// A letterspaced overline followed by a rule that runs to the margin.
///
/// The rule is what makes a section heading read as typography rather than as
/// a label: it gives the eye a horizontal to hang the section from without
/// spending a heavier weight or a larger size on the word itself. Used for
/// every section break in the app so the vertical rhythm stays the same
/// whether the section holds offers, rooms or results.
class SectionHeading extends StatelessWidget {
  const SectionHeading({
    required this.label,
    this.padding = const EdgeInsets.fromLTRB(20, 26, 20, 14),
    this.trailing,
    super.key,
  });

  final String label;
  final EdgeInsets padding;

  /// Optional widget set after the rule — a count, a link, an action.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          Text(label, style: theme.textTheme.labelSmall),
          const SizedBox(width: 12),
          Expanded(
            child: Divider(
              height: 1,
              thickness: 1,
              color: theme.colorScheme.outlineVariant,
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
  }
}

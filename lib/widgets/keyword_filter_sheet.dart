import 'package:flutter/material.dart';

import '../theme/hud_palette.dart';

/// What the reader chose to do with the keyword filter.
class KeywordFilterResult {
  const KeywordFilterResult(this.terms);

  /// Empty means "show everything again".
  final String terms;

  bool get cleared => terms.trim().isEmpty;
}

/// Asks for the words every satellite must match.
///
/// Presented as a sheet rather than a dialog so the keyboard has room on a
/// small phone, and so the current constraint stays visible while editing.
class KeywordFilterSheet extends StatefulWidget {
  const KeywordFilterSheet({super.key, required this.initial});

  final String initial;

  static Future<KeywordFilterResult?> show(
    BuildContext context, {
    required String initial,
  }) =>
      showModalBottomSheet<KeywordFilterResult>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => KeywordFilterSheet(initial: initial),
      );

  @override
  State<KeywordFilterSheet> createState() => _KeywordFilterSheetState();
}

class _KeywordFilterSheetState extends State<KeywordFilterSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply() => Navigator.of(context)
      .pop(KeywordFilterResult(_controller.text.trim()));

  void _clear() => Navigator.of(context).pop(const KeywordFilterResult(''));

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: HudPalette.deepField,
          border: Border(
            top: BorderSide(color: Color(0x3356E8FF), width: 1),
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CONSTRAIN EXPLORATION',
                style: HudPalette.telemetry.copyWith(letterSpacing: 2.2)),
            const SizedBox(height: 14),
            const Text(
              'Only show satellites whose name or description mentions every '
              'word you enter. Fewer words match more.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: Color(0xFF8AA5B3),
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _apply(),
              style: const TextStyle(fontSize: 17, color: HudPalette.ice),
              cursorColor: HudPalette.aqua,
              decoration: InputDecoration(
                hintText: 'electric guitar',
                hintStyle: TextStyle(
                  color: HudPalette.aquaDim.withValues(alpha: 0.6),
                ),
                filled: true,
                fillColor: HudPalette.voidBlack,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: HudPalette.aqua.withValues(alpha: 0.25),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: HudPalette.aqua.withValues(alpha: 0.65),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _SheetButton(
                    label: 'SHOW EVERYTHING',
                    onTap: _clear,
                    filled: false,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SheetButton(
                    label: 'APPLY',
                    onTap: _apply,
                    filled: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.onTap,
    required this.filled,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: HudPalette.aqua.withValues(alpha: filled ? 0.6 : 0.28),
          ),
          color: HudPalette.aqua.withValues(alpha: filled ? 0.16 : 0.03),
        ),
        child: Text(
          label,
          style: HudPalette.telemetry.copyWith(
            color: filled ? HudPalette.aqua : HudPalette.aquaDim,
          ),
        ),
      ),
    );
  }
}

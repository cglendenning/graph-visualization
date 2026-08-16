import 'package:flutter/material.dart';

import '../theme/hud_palette.dart';

/// What the reader chose to do with the theme filter.
class KeywordFilterResult {
  const KeywordFilterResult(this.terms);

  /// Empty means "show everything again".
  final String terms;

  bool get cleared => terms.trim().isEmpty;
}

/// Asks for a subject to steer exploration toward.
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

  bool _explaining = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply() =>
      Navigator.of(context).pop(KeywordFilterResult(_controller.text.trim()));

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
          border: Border(top: BorderSide(color: Color(0x3356E8FF))),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('STEER TOWARD A SUBJECT',
                style: HudPalette.telemetry.copyWith(letterSpacing: 2.2)),
            const SizedBox(height: 14),
            const Text(
              'Name a subject and exploration leans toward it.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: Color(0xFF8AA5B3),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _explaining = !_explaining),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  _explaining ? 'HIDE DETAIL' : 'WHAT DOES THIS DO?',
                  style: HudPalette.telemetry.copyWith(
                    color: HudPalette.aqua,
                    decoration: TextDecoration.underline,
                    decorationColor: HudPalette.aqua.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
            if (_explaining) ...[
              const SizedBox(height: 12),
              const _Explainer(),
            ],
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _apply(),
              style: const TextStyle(fontSize: 17, color: HudPalette.ice),
              cursorColor: HudPalette.aqua,
              decoration: InputDecoration(
                hintText: 'jazz',
                hintStyle: TextStyle(
                  color: HudPalette.aquaDim.withValues(alpha: 0.6),
                ),
                filled: true,
                fillColor: HudPalette.voidBlack,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: HudPalette.aqua.withValues(alpha: 0.25)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: HudPalette.aqua.withValues(alpha: 0.65)),
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
                    label: 'STEER',
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

/// Sets expectations honestly, including where steering is weak.
class _Explainer extends StatelessWidget {
  const _Explainer();

  static const _lines = [
    'Your words are matched to a subject on Wikipedia, and everything '
        'written about that subject becomes the theme.',
    'Satellites inside the theme take the seats first, so the rosette leans '
        'the way you pointed it.',
    'It is a pull, not a fence. Any seats the theme cannot fill are taken by '
        'ordinary neighbours, so you never get an empty screen and you can '
        'always wander back out.',
    'The footer shows how many of the six came from your subject.',
    'Specific subjects hold better than broad ones. "Jazz" or "electric '
        'guitar" stay on theme for a long walk; something as broad as "food" '
        'drifts after a hop or two.',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HudPalette.aqua.withValues(alpha: 0.18)),
        color: HudPalette.voidBlack.withValues(alpha: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in _lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 10),
                    child: Container(
                      width: 3,
                      height: 3,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: HudPalette.aqua.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      line,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: Color(0xFF8AA5B3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
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

import 'package:flutter/material.dart';

import '../theme/hud_palette.dart';

/// What the reader chose in the new-topic sheet.
sealed class NewTopicChoice {
  const NewTopicChoice();
}

/// Go somewhere random. Usually already drawn and waiting.
class RandomTopic extends NewTopicChoice {
  const RandomTopic();
}

/// Go to a named subject.
class NamedTopic extends NewTopicChoice {
  const NamedTopic(this.phrase);

  final String phrase;
}

/// Asks where to go next: somewhere named, or somewhere random.
class NewTopicSheet extends StatefulWidget {
  const NewTopicSheet({super.key, required this.randomReady});

  /// Whether a random topic is already drawn, shown as the readiness dot.
  final bool randomReady;

  static Future<NewTopicChoice?> show(
    BuildContext context, {
    required bool randomReady,
  }) =>
      showModalBottomSheet<NewTopicChoice>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => NewTopicSheet(randomReady: randomReady),
      );

  @override
  State<NewTopicSheet> createState() => _NewTopicSheetState();
}

class _NewTopicSheetState extends State<NewTopicSheet> {
  final TextEditingController _controller = TextEditingController();

  bool get _hasText => _controller.text.trim().isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go() {
    if (!_hasText) return;
    Navigator.of(context).pop(NamedTopic(_controller.text.trim()));
  }

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
            Text('NEW TOPIC',
                style: HudPalette.telemetry.copyWith(letterSpacing: 2.2)),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.go,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _go(),
              style: const TextStyle(fontSize: 17, color: HudPalette.ice),
              cursorColor: HudPalette.aqua,
              decoration: InputDecoration(
                hintText: 'name a topic',
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
                    label: 'CANCEL',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: _SheetButton(
                    label: 'RANDO TOPIC',
                    ready: widget.randomReady,
                    onTap: () =>
                        Navigator.of(context).pop(const RandomTopic()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SheetButton(
                    label: 'GO',
                    // Only lit once there is something to go to.
                    filled: _hasText,
                    onTap: _hasText ? _go : null,
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
    this.filled = false,
    this.ready = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final border = filled ? 0.6 : (enabled ? 0.28 : 0.10);
    final fill = filled ? 0.16 : 0.03;
    final text = filled
        ? HudPalette.aqua
        : enabled
            ? HudPalette.aquaDim
            : HudPalette.aquaDim.withValues(alpha: 0.35);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: HudPalette.aqua.withValues(alpha: border)),
          color: HudPalette.aqua.withValues(alpha: fill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ready) ...[
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: HudPalette.aqua.withValues(alpha: 0.85),
                  boxShadow: [
                    BoxShadow(
                      color: HudPalette.aqua.withValues(alpha: 0.6),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HudPalette.telemetry.copyWith(color: text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/wikipedia_extract.dart';
import '../theme/hud_palette.dart';

/// Provenance and licence notices.
///
/// Two obligations are met here. The graph's own provenance is stated, and
/// the bundled open-source packages get their required copyright notices via
/// Flutter's licence registry — BSD-3-Clause, MIT and Apache-2.0 all require
/// those notices to travel with a binary distribution.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, required this.nodeCount});

  final int nodeCount;

  static Route<void> route({required int nodeCount}) =>
      CupertinoPageRoute<void>(
        builder: (_) => AboutScreen(nodeCount: nodeCount),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HudPalette.voidBlack,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: HudPalette.field(HudPalette.aqua)),
        child: SafeArea(
          child: Column(
            children: [
              _BackBar(onBack: () => Navigator.of(context).pop()),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
                  children: [
                    Text(
                      'Perihelion',
                      style: HudPalette.nodeName.copyWith(fontSize: 24),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Traverse a knowledge graph, one node at a time.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        fontStyle: FontStyle.italic,
                        color: HudPalette.aqua.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 30),
                    const _Label('THE GRAPH'),
                    const SizedBox(height: 12),
                    _Body(
                      '$nodeCount nodes, their categories, relationships and '
                      'facts were written for this app. Facts themselves are '
                      'not owned by anyone; the wording, the choice of links '
                      'and their weights are original work.',
                    ),
                    const SizedBox(height: 26),
                    const _Label('ARTICLE SUMMARIES'),
                    const SizedBox(height: 12),
                    _Body(
                      'Summaries are not bundled with this app. When you open '
                      'a node, the opening section of the matching English '
                      'Wikipedia article is fetched and shown verbatim, '
                      'credited to that article and to its licence.',
                    ),
                    const SizedBox(height: 12),
                    _Body(
                      'Wikipedia text is used under '
                      '${WikipediaExtract.licenseName}. Opening a node sends a '
                      'request to Wikipedia; nothing else leaves the device, '
                      'and the app collects nothing.',
                    ),
                    const SizedBox(height: 26),
                    const _Label('SOFTWARE'),
                    const SizedBox(height: 12),
                    _Body(
                      'Built with Flutter and a small number of open-source '
                      'packages, all under permissive licences that require '
                      'their copyright notices to be reproduced.',
                    ),
                    const SizedBox(height: 16),
                    _Action(
                      label: 'OPEN SOURCE LICENCES',
                      // No version string here: it would be a second copy of
                      // the number in pubspec.yaml, free to drift out of date.
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: 'Perihelion',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackBar extends StatelessWidget {
  const _BackBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onBack,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.chevron_left,
                    size: 16, color: HudPalette.aquaDim),
                SizedBox(width: 5),
                Text('BACK', style: HudPalette.telemetry),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: HudPalette.telemetry.copyWith(letterSpacing: 2.2));
}

class _Body extends StatelessWidget {
  const _Body(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          height: 1.6,
          color: Color(0xFFB9CBD6),
        ),
      );
}

class _Action extends StatelessWidget {
  const _Action({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: HudPalette.aqua.withValues(alpha: 0.35)),
          color: HudPalette.aqua.withValues(alpha: 0.05),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: HudPalette.telemetry.copyWith(color: HudPalette.aqua),
        ),
      ),
    );
  }
}

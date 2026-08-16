import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/wikipedia_extract.dart';
import '../services/wikipedia_service.dart';
import '../theme/hud_palette.dart';

/// Renders the Wikipedia lead section for one article, with the credit line
/// CC BY-SA 4.0 requires.
///
/// The rest of the detail screen renders immediately; only this block waits,
/// so a slow network never blocks the reader from the facts or connections.
class WikipediaSection extends StatefulWidget {
  const WikipediaSection({
    super.key,
    required this.service,
    required this.title,
    required this.hue,
  });

  final WikipediaService service;
  final String title;
  final Color hue;

  @override
  State<WikipediaSection> createState() => _WikipediaSectionState();
}

class _WikipediaSectionState extends State<WikipediaSection> {
  late Future<WikipediaExtract> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.service.extractFor(widget.title);
  }

  void _retry() {
    setState(() => _future = widget.service.extractFor(widget.title));
  }

  Future<void> _open(Uri url) async {
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      // Surfaced rather than swallowed: the reader needs to know the tap did
      // nothing, and the URL is shown beneath so it stays reachable.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: HudPalette.deepField,
          content: Text(
            'Could not open $url',
            style: HudPalette.telemetry.copyWith(color: HudPalette.ice),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WikipediaExtract>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _Skeleton();
        }
        if (snapshot.hasError) {
          final error = snapshot.error;
          return _Failed(
            message: error is WikipediaUnavailable
                ? error.message
                : 'Could not load the Wikipedia extract.',
            onRetry: _retry,
          );
        }
        return _Loaded(
          extract: snapshot.requireData,
          hue: widget.hue,
          onOpen: _open,
        );
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({
    required this.extract,
    required this.hue,
    required this.onOpen,
  });

  final WikipediaExtract extract;
  final Color hue;
  final Future<void> Function(Uri) onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          extract.text,
          style: const TextStyle(
            fontSize: 15,
            height: 1.62,
            color: Color(0xFFB9CBD6),
          ),
        ),
        const SizedBox(height: 16),
        // Required attribution: the source, and the license it carries.
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Link(
              label: extract.attribution,
              hue: hue,
              onTap: () => onOpen(extract.articleUrl),
            ),
            Text('  ·  ', style: HudPalette.relation),
            _Link(
              label: WikipediaExtract.licenseName,
              hue: hue,
              onTap: () => onOpen(WikipediaExtract.licenseUrl),
            ),
          ],
        ),
      ],
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.label, required this.hue, required this.onTap});

  final String label;
  final Color hue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: HudPalette.relation.copyWith(
          color: hue.withValues(alpha: 0.9),
          decoration: TextDecoration.underline,
          decorationColor: hue.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final width in const [1.0, 0.96, 0.99, 0.62])
          Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: FractionallySizedBox(
              widthFactor: width,
              child: Container(
                height: 9,
                decoration: BoxDecoration(
                  color: HudPalette.aqua.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        const SizedBox(height: 5),
        Text('FETCHING EXTRACT', style: HudPalette.telemetry),
      ],
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: const TextStyle(
            fontSize: 14,
            height: 1.55,
            color: Color(0xFF7E97A4),
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: onRetry,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: HudPalette.aqua.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              'RETRY',
              style: HudPalette.telemetry.copyWith(color: HudPalette.aqua),
            ),
          ),
        ),
      ],
    );
  }
}

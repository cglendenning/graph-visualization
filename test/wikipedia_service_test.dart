import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:perihelion/models/wikipedia_extract.dart';
import 'package:perihelion/services/wikipedia_service.dart';

String _ok(String title, String extract) => jsonEncode({
      'query': {
        'pages': [
          {'pageid': 1, 'title': title, 'extract': extract},
        ],
      },
    });

void main() {
  group('WikipediaService', () {
    test('builds the extracts endpoint with plain-text intro and redirects',
        () {
      final url = WikipediaService.endpointFor('Vienna');
      expect(url.host, 'en.wikipedia.org');
      expect(url.path, '/w/api.php');
      expect(url.queryParameters['titles'], 'Vienna');
      expect(url.queryParameters['prop'], 'extracts');
      expect(url.queryParameters['exintro'], '1');
      expect(url.queryParameters['explaintext'], '1');
      expect(url.queryParameters['redirects'], '1');
    });

    test('builds an article url with underscores for spaces', () {
      final url = WikipediaService.articleUrlFor('The Kiss (Klimt)');
      expect(url.toString(), contains('The_Kiss'));
      expect(url.host, 'en.wikipedia.org');
    });

    test('returns the extract text and canonical title', () async {
      final service = WikipediaService(
        fetcher: (_) async => _ok('Vienna', 'Vienna is the capital.'),
      );
      final extract = await service.extractFor('Vienna');
      expect(extract.text, 'Vienna is the capital.');
      expect(extract.title, 'Vienna');
      expect(extract.articleUrl.toString(), contains('Vienna'));
    });

    test('adopts the canonical title when a redirect was followed', () async {
      final service = WikipediaService(
        fetcher: (_) async => _ok('Napoleon', 'Napoleon was a general.'),
      );
      final extract = await service.extractFor('Napoleon Bonaparte');
      expect(extract.title, 'Napoleon');
      expect(extract.attribution, '"Napoleon" on Wikipedia');
    });

    test('carries the licence the attribution requires', () async {
      final service = WikipediaService(
        fetcher: (_) async => _ok('Vienna', 'Text.'),
      );
      final extract = await service.extractFor('Vienna');
      expect(WikipediaExtract.licenseName, 'CC BY-SA 4.0');
      expect(
        WikipediaExtract.licenseUrl.toString(),
        'https://creativecommons.org/licenses/by-sa/4.0/',
      );
      expect(extract.attribution, contains('Wikipedia'));
    });

    test('fetches once per title and serves the rest from cache', () async {
      var calls = 0;
      final service = WikipediaService(fetcher: (_) async {
        calls++;
        return _ok('Vienna', 'Text.');
      });
      await service.extractFor('Vienna');
      await service.extractFor('Vienna');
      await service.extractFor('Vienna');
      expect(calls, 1);
      expect(service.isCached('Vienna'), isTrue);
      expect(service.isCached('Florence'), isFalse);
    });

    test('reports a missing article without caching it', () async {
      final service = WikipediaService(
        fetcher: (_) async => jsonEncode({
          'query': {
            'pages': [
              {'title': 'Nope', 'missing': true},
            ],
          },
        }),
      );
      await expectLater(
        service.extractFor('Nope'),
        throwsA(isA<WikipediaUnavailable>().having(
          (e) => e.message,
          'message',
          contains('No Wikipedia article'),
        )),
      );
      expect(service.isCached('Nope'), isFalse);
    });

    test('reports an article with no summary text', () async {
      final service = WikipediaService(
        fetcher: (_) async => _ok('Bare', '   '),
      );
      await expectLater(
        service.extractFor('Bare'),
        throwsA(isA<WikipediaUnavailable>()),
      );
    });

    test('reports an empty page list', () async {
      final service = WikipediaService(
        fetcher: (_) async => jsonEncode({
          'query': {'pages': <dynamic>[]},
        }),
      );
      await expectLater(
        service.extractFor('Vienna'),
        throwsA(isA<WikipediaUnavailable>()),
      );
    });

    test('reports unreadable json rather than throwing a raw FormatException',
        () async {
      final service = WikipediaService(fetcher: (_) async => 'not json at all');
      await expectLater(
        service.extractFor('Vienna'),
        throwsA(isA<WikipediaUnavailable>().having(
          (e) => e.message,
          'message',
          contains('unreadable'),
        )),
      );
    });

    test('turns a network failure into an actionable message', () async {
      final service = WikipediaService(
        fetcher: (_) async => throw const SocketishError(),
      );
      await expectLater(
        service.extractFor('Vienna'),
        throwsA(isA<WikipediaUnavailable>().having(
          (e) => e.message,
          'message',
          contains('Check your connection'),
        )),
      );
    });

    test('keeps the original error as the cause for debugging', () async {
      final service = WikipediaService(
        fetcher: (_) async => throw const SocketishError(),
      );
      try {
        await service.extractFor('Vienna');
        fail('expected WikipediaUnavailable');
      } on WikipediaUnavailable catch (e) {
        expect(e.cause, isA<SocketishError>());
        expect(e.toString(), contains('WikipediaUnavailable'));
      }
    });

    test('declares a descriptive user agent, as Wikimedia policy requires',
        () {
      expect(WikipediaService.userAgent, contains('Perihelion'));
      expect(WikipediaService.userAgent, contains('https://'));
    });
  });
}

/// Stands in for a transport failure without importing dart:io into the test.
class SocketishError implements Exception {
  const SocketishError();
}

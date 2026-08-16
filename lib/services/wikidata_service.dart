import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models/node_category.dart';
import '../models/wikidata_node.dart';
import 'wikidata_category_map.dart';

typedef UrlFetcher = Future<String> Function(Uri url);

/// Reads the rosette straight out of Wikidata.
///
/// Wikidata states each fact once, on whichever item it belongs to — a person
/// records the city they were born in, the city records nothing about them.
/// So neighbours are gathered in both directions, and the incoming direction
/// is where almost all the interesting edges live.
///
/// Vienna alone has over 180,000 incoming statements, far too many to fetch.
/// Instead the properties are listed first (cheap), a handful are chosen at
/// random, and one neighbour is drawn at random from each. That is
/// what makes a second visit to the same topic look different.
class WikidataService {
  WikidataService({UrlFetcher? fetcher, Random? random})
      : _fetch = fetcher ?? _httpFetch,
        _random = random ?? Random();

  final UrlFetcher _fetch;
  final Random _random;

  final Map<String, List<PropertyLink>> _propertyCache = {};
  final Map<String, WikidataNode> _nodeCache = {};

  static const Duration timeout = Duration(seconds: 20);

  static const String userAgent =
      'Perihelion/2.0 (https://github.com/cglendenning/graph-visualization)';

  static const int seatCount = 6;

  /// How many rows to pull per property before picking one at random.
  ///
  ///
  /// Most properties hold only one or two statements, so any offset at all
  /// runs off the end and returns nothing. Variety comes instead from which
  /// properties are drawn — there are typically 60 to 130 to choose six from,
  /// which is combinatorially far more than enough — and from picking at
  /// random among the rows each one returns.
  static const int candidatesPerProperty = 10;

  /// Properties are sampled well beyond the number of seats, because a
  /// property can hold only statements whose targets have no article and so
  /// contribute nothing after filtering.
  static const int propertiesSampled = seatCount * 2;

  /// Properties that describe Wikimedia's own bookkeeping rather than the
  /// subject, plus a few that are true but never interesting to look at.
  static const Set<String> blockedProperties = {
    'P31', // instance of — the category chip already says this
    'P279', // subclass of
    'P910', // topic's main category
    'P1424', // topic's main template
    'P1343', // described by source
    'P5008', // on focus list of Wikimedia project
    'P373', // Commons category
    'P935', // Commons gallery
    'P8408', // KBpedia
    'P1889', // different from
    'P460', // said to be the same as
    'P1382', // partially coincident with
    'P2860', // cites work
    'P921', // main subject (fires on millions of papers)
    'P1445', // fictional universe described in
    'P527', // has part — usually administrative
    'P361', // part of
    'P17', // country — true of nearly everything, says little
  };

  static final RegExp _qid = RegExp(r'^Q\d+$');
  static final RegExp _pid = RegExp(r'^P\d+$');

  // ---------------------------------------------------------------- queries

  static Uri sparqlUrl(String query) => Uri.https(
        'query.wikidata.org',
        '/sparql',
        {'query': query, 'format': 'json'},
      );

  static Uri randomArticleUrl() =>
      Uri.https('en.wikipedia.org', '/w/api.php', {
        'action': 'query',
        'format': 'json',
        'formatversion': '2',
        'generator': 'random',
        'grnnamespace': '0',
        'grnlimit': '1',
        'prop': 'pageprops',
        'ppprop': 'wikibase_item',
      });

  /// A random topic from the whole of English Wikipedia.
  ///
  /// Drawn from Wikipedia rather than Wikidata directly: a third of Wikidata
  /// is bot-imported scholarly records, so a raw random item is almost never
  /// something a person would want to land on.
  Future<String> randomStartQid() async {
    final body = await _get(randomArticleUrl());
    final json = _decode(body);
    final pages = (json['query'] as Map<String, dynamic>?)?['pages'];
    if (pages is! List || pages.isEmpty) {
      throw const WikidataUnavailable('Wikipedia returned no random article.');
    }
    final qid = ((pages.first as Map<String, dynamic>)['pageprops']
        as Map<String, dynamic>?)?['wikibase_item'] as String?;
    if (qid == null || !_qid.hasMatch(qid)) {
      // Some articles have no Wikidata item; drawing again is cheaper than
      // reasoning about which ones.
      return randomStartQid();
    }
    return qid;
  }

  /// Label, description and category for one item.
  Future<WikidataNode> node(String qid) async {
    _requireQid(qid);
    final cached = _nodeCache[qid];
    if (cached != null) return cached;

    final query = '''
SELECT ?label ?description ?type WHERE {
  OPTIONAL { wd:$qid rdfs:label ?label . FILTER(lang(?label) = "en") }
  OPTIONAL { wd:$qid schema:description ?description . FILTER(lang(?description) = "en") }
  OPTIONAL { wd:$qid wdt:P31 ?type }
}
LIMIT 20''';

    final rows = await _select(query);
    if (rows.isEmpty) {
      throw WikidataUnavailable('Wikidata has no item $qid.');
    }
    final label = _value(rows.first, 'label') ?? qid;
    final description = _value(rows.first, 'description') ?? '';
    final types = rows
        .map((r) => _value(r, 'type'))
        .whereType<String>()
        .map(_localName)
        .toList(growable: false);

    final result = WikidataNode(
      qid: qid,
      label: label,
      description: description,
      category: WikidataCategoryMap.forTypes(types),
    );
    _nodeCache[qid] = result;
    return result;
  }

  /// Every property with at least one statement joining [qid] to another
  /// item, in either direction. Cached: this does not change between visits.
  Future<List<PropertyLink>> propertiesFor(String qid) async {
    _requireQid(qid);
    final cached = _propertyCache[qid];
    if (cached != null) return cached;

    final query = '''
SELECT DISTINCT ?pd ?dir WHERE {
  {
    SELECT DISTINCT ?pd ("out" AS ?dir) WHERE {
      wd:$qid ?pd ?o . ?prop wikibase:directClaim ?pd .
      FILTER(isIRI(?o))
    }
  } UNION {
    SELECT DISTINCT ?pd ("in" AS ?dir) WHERE {
      ?s ?pd wd:$qid . ?prop wikibase:directClaim ?pd .
    }
  }
}
LIMIT 200''';

    final rows = await _select(query);
    final links = <PropertyLink>[];
    for (final row in rows) {
      final pid = _localName(_value(row, 'pd') ?? '');
      if (!_pid.hasMatch(pid) || blockedProperties.contains(pid)) continue;
      links.add(PropertyLink(pid: pid, incoming: _value(row, 'dir') == 'in'));
    }
    _propertyCache[qid] = links;
    return links;
  }

  /// Draws up to six neighbours, at most one per property.
  ///
  /// Randomised twice over — which properties are drawn, and which of each
  /// property's rows is taken — so the same centre yields a different rosette
  /// each time it is visited.
  Future<List<WikidataNeighbor>> sampleNeighbors(String qid) async {
    final links = await propertiesFor(qid);
    if (links.isEmpty) return const [];

    final pool = List<PropertyLink>.of(links)..shuffle(_random);
    final picked = pool.take(propertiesSampled).toList(growable: false);

    final blocks = picked.map((link) {
      final pattern = link.incoming
          ? '?other wdt:${link.pid} wd:$qid .'
          : 'wd:$qid wdt:${link.pid} ?other .';
      return '''
  {
    SELECT ?pd ?dir ?other WHERE {
      BIND(wdt:${link.pid} AS ?pd) BIND("${link.incoming ? 'in' : 'out'}" AS ?dir)
      $pattern
      ?sl${link.pid} schema:about ?other ; schema:isPartOf <https://en.wikipedia.org/> .
    }
    LIMIT $candidatesPerProperty
  }''';
    }).join('\n  UNION');

    final query = '''
SELECT ?pd ?dir ?other ?otherLabel ?propLabel ?type WHERE {
$blocks
  ?prop wikibase:directClaim ?pd .
  OPTIONAL { ?other wdt:P31 ?type }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
LIMIT 400''';

    final rows = await _select(query);
    return _toNeighbors(rows, qid);
  }

  List<WikidataNeighbor> _toNeighbors(
    List<Map<String, dynamic>> rows,
    String centerQid,
  ) {
    // Group by property so a single property cannot take every seat, and
    // collect P31 values that arrived across several rows.
    final grouped = <String, List<Map<String, dynamic>>>{};
    final types = <String, List<String>>{};
    for (final row in rows) {
      final other = _localName(_value(row, 'other') ?? '');
      if (!_qid.hasMatch(other) || other == centerQid) continue;
      final key = '${_localName(_value(row, 'pd') ?? '')}|${_value(row, 'dir')}';
      (grouped[key] ??= []).add(row);
      final type = _value(row, 'type');
      if (type != null) (types[other] ??= []).add(_localName(type));
    }

    final result = <WikidataNeighbor>[];
    final taken = <String>{};
    for (final entry in grouped.entries) {
      final candidates = entry.value
          .where((r) => !taken.contains(_localName(_value(r, 'other')!)))
          .toList();
      if (candidates.isEmpty) continue;
      final row = candidates[_random.nextInt(candidates.length)];
      final qid = _localName(_value(row, 'other')!);
      taken.add(qid);

      final label = _value(row, 'otherLabel') ?? qid;
      if (label == qid) continue; // unlabelled item, nothing to show
      result.add(WikidataNeighbor(
        node: WikidataNode(
          qid: qid,
          label: label,
          description: '',
          category: WikidataCategoryMap.forTypes(types[qid] ?? const []),
        ),
        relation: _value(row, 'propLabel') ?? 'related to',
        incoming: _value(row, 'dir') == 'in',
      ));
      if (result.length == seatCount) break;
    }
    return result;
  }

  // ------------------------------------------------------------- plumbing

  void _requireQid(String qid) {
    if (!_qid.hasMatch(qid)) {
      throw ArgumentError('Not a Wikidata item id: $qid');
    }
  }

  static String _localName(String iri) =>
      iri.contains('/') ? iri.split('/').last : iri;

  static String? _value(Map<String, dynamic> row, String key) =>
      (row[key] as Map<String, dynamic>?)?['value'] as String?;

  Future<List<Map<String, dynamic>>> _select(String query) async {
    final body = await _get(sparqlUrl(query));
    final json = _decode(body);
    final bindings =
        (json['results'] as Map<String, dynamic>?)?['bindings'] as List<dynamic>?;
    if (bindings == null) {
      throw const WikidataUnavailable('Wikidata returned no results block.');
    }
    return bindings.cast<Map<String, dynamic>>();
  }

  Map<String, dynamic> _decode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } on FormatException catch (error) {
      throw WikidataUnavailable(
        'Wikidata returned an unreadable response.',
        cause: error,
      );
    }
  }

  Future<String> _get(Uri url) async {
    try {
      return await _fetch(url).timeout(timeout);
    } on WikidataUnavailable {
      rethrow;
    } on Object catch (error) {
      throw WikidataUnavailable(
        'Could not reach Wikidata. Check your connection and try again.',
        cause: error,
      );
    }
  }

  static Future<String> _httpFetch(Uri url) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(url);
      request.headers
        ..set(HttpHeaders.userAgentHeader, userAgent)
        ..set(HttpHeaders.acceptHeader, 'application/sparql-results+json');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Wikidata responded ${response.statusCode}',
            uri: url);
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }
}

/// Convenience for the UI, which colours by category.
extension WikidataNodeColor on WikidataNode {
  NodeCategory get resolvedCategory => category;
}

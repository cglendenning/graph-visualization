import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

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

  /// Rosettes drawn ahead of time for satellites currently on screen.
  ///
  /// Consumed on use rather than kept: the draw is meant to be random, so a
  /// later return to the same topic should produce a different six.
  final Map<String, List<WikidataNeighbor>> _readyDraws = {};

  final List<String> _prefetchQueue = <String>[];
  final Set<String> _prefetching = <String>{};

  /// Prefetches running at once.
  ///
  /// Deliberately below the six satellites on screen. Each prefetch is three
  /// queries, and firing eighteen at a public endpoint in one burst is both
  /// discourteous and a good way to get throttled. Three at a time still
  /// warms every satellite within a few seconds of the rosette appearing.
  static const int maxConcurrentPrefetch = 3;

  /// Entries held before the oldest are dropped, so a long session cannot
  /// grow the caches without bound.
  static const int maxCacheEntries = 240;

  static const Duration timeout = Duration(seconds: 20);

  static const String userAgent =
      'Perihelion/2.4 (https://github.com/cglendenning/graph-visualization)';

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
  /// contribute nothing after filtering. Widened rather than repeated: one
  /// larger query costs far less than several small ones in sequence.
  static const int propertiesSampled = 18;

  /// How widely covered a neighbour must be to take a seat, tried in order.
  ///
  /// Wikidata records how many language Wikipedias carry an article for each
  /// item, which is the best cheap proxy for whether a person has heard of
  /// it. Filtering on it costs nothing — it prunes before the join, so a
  /// filtered query is no slower than an unfiltered one — whereas sorting by
  /// it takes seven seconds and is unaffordable.
  ///
  /// Forty is roughly "known outside its own country": for Vienna's natives
  /// it yields Karl Popper and Melanie Klein rather than a local pop singer.
  /// The lower tiers exist so a modest topic can still fill its seats.
  static const List<int> notabilityTiers = [40, 12, 0];

  /// Slices of the property list to try before giving up on the neat path.
  ///
  /// Without this a well-connected topic could run a dozen queries back to
  /// back, each a second or two, and the jump would appear to hang.
  static const int maxRounds = 3;

  /// Total time one rosette may spend querying before it settles for what it
  /// already has. A partly filled rosette beats a spinner.
  static const Duration sampleBudget = Duration(seconds: 14);

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
    'P971', // category combines topics
    'P301', // category's main topic
    'P4224', // category contains
    'P1754', // category related to list
    'P6365', // member category
  };

  /// Wikimedia's own pages — categories, list articles, templates,
  /// disambiguation stubs. They carry sitelinks, so the notability filter
  /// lets them through; they are excluded by what they are instead.
  static const List<String> wikimediaInternalTypes = [
    'Q4167836', // Wikimedia category
    'Q13406463', // Wikimedia list article
    'Q11266439', // Wikimedia template
    'Q4167410', // Wikimedia disambiguation page
    'Q17442446', // Wikimedia internal item
    'Q11753321', // Wikimedia navigational template
  ];

  static final RegExp _qid = RegExp(r'^Q\d+$');
  static final RegExp _pid = RegExp(r'^P\d+$');

  List<String> _keywords = const [];

  /// Words every satellite must match, or empty for unconstrained browsing.
  List<String> get keywords => List<String>.unmodifiable(_keywords);

  /// Narrows exploration to neighbours mentioning all of [terms].
  ///
  /// Matching is against the label *and* the description together, which
  /// matters more than it sounds: nobody born in Vienna is called "music",
  /// but plenty are described as musicians. Label-only matching returns
  /// almost nothing.
  ///
  /// Changing the filter discards anything already warmed, since those draws
  /// were made under the previous constraint.
  void setKeywords(String input) {
    final terms = input
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.length > 1)
        .take(4)
        .toList(growable: false);
    if (_sameTerms(terms, _keywords)) return;
    _keywords = terms;
    _readyDraws.clear();
    _prefetchQueue.clear();
  }

  bool get isFiltered => _keywords.isNotEmpty;

  static bool _sameTerms(List<String> a, List<String> b) =>
      a.length == b.length &&
      List<int>.generate(a.length, (i) => i).every((i) => a[i] == b[i]);

  /// When a keyword filter is on, most properties return nothing, so the
  /// search has to look at far more of them.
  ///
  /// A keyword is already a strong constraint. Stacking the notability bar
  /// and the must-have-an-article rule on top of it left almost nothing
  /// alive: searching "food" from the food article returned one satellite.
  /// Under a filter those two are dropped and the coverage widened instead.
  /// Ten, not more: the keyword clause is repeated per property, and twelve
  /// pushes the request past the URL ceiling, where it gets trimmed straight
  /// back down again. Coverage comes from more rounds instead — each query
  /// stays sub-second, so six of them is still quick.
  static const int filteredPropertiesSampled = 10;
  static const int filteredMaxRounds = 6;
  static const List<int> filteredNotabilityTiers = [0, 0, 0, 0, 0, 0];

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
    // With a filter on, a purely random article is almost never about the
    // subject asked for, and its rosette comes back empty. Seed from the
    // keywords instead so a new topic lands inside the constraint.
    if (isFiltered) {
      final seeded = await _searchStartQid();
      if (seeded != null) return seeded;
    }
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

  /// Picks a topic matching the active keywords, using Wikidata's own search
  /// index rather than scanning the graph.
  ///
  /// Returns null when the words match nothing, so the caller can fall back
  /// to an unconstrained topic rather than failing outright.
  Future<String?> _searchStartQid() async {
    final phrase = _keywords.join(' ').replaceAll('"', '');
    if (phrase.isEmpty) return null;

    final rows = await _select('''
SELECT ?item WHERE {
  SERVICE wikibase:mwapi {
    bd:serviceParam wikibase:endpoint "www.wikidata.org" ;
                    wikibase:api "EntitySearch" ;
                    mwapi:search "$phrase" ;
                    mwapi:language "en" ;
                    mwapi:limit "30" .
    ?item wikibase:apiOutputItem mwapi:item .
  }
  ?sl schema:about ?item ; schema:isPartOf <https://en.wikipedia.org/> .
  FILTER NOT EXISTS { ?item wdt:P31 ?internal .
    VALUES ?internal { ${wikimediaInternalTypes.map((q) => 'wd:$q').join(' ')} } }
}
LIMIT 30''');

    final candidates = rows
        .map((r) => _localName(_value(r, 'item') ?? ''))
        .where(_qid.hasMatch)
        .toList(growable: false);
    if (candidates.isEmpty) return null;
    return candidates[_random.nextInt(candidates.length)];
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
    _remember(_nodeCache, qid, result);
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
    LIMIT 100
  } UNION {
    SELECT DISTINCT ?pd ("in" AS ?dir) WHERE {
      ?s ?pd wd:$qid . ?prop wikibase:directClaim ?pd .
    }
    LIMIT 100
  }
}
LIMIT 200''';

    final rows = await _select(query);
    final links = <PropertyLink>[];
    for (final row in rows) {
      final pid = _localName(_value(row, 'pd') ?? '');
      if (!_pid.hasMatch(pid)) continue;
      // Blocked properties are kept here and filtered when sampling, so the
      // last-resort pass can still reach them rather than leaving a seat empty.
      links.add(PropertyLink(pid: pid, incoming: _value(row, 'dir') == 'in'));
    }
    _remember(_propertyCache, qid, links);
    return links;
  }

  /// Draws six neighbours, as varied as the data allows.
  ///
  /// Filling all six matters more than any single preference, so the seats
  /// are filled in descending order of pickiness:
  ///
  ///  1. one per property, each a category not yet on screen
  ///  2. one per property, any category
  ///  3. anything left over, so a rich property can cover for sparse ones
  ///
  /// If the drawn properties still cannot fill six, another slice of the
  /// property list is drawn, and finally the filters themselves are relaxed.
  Future<List<WikidataNeighbor>> sampleNeighbors(String qid) async {
    // A draw warmed while the user was reading is taken as-is, which is what
    // makes the jump feel immediate. It is removed on use so that coming back
    // here later draws afresh.
    final ready = _readyDraws.remove(qid);
    if (ready != null && ready.isNotEmpty) return ready;
    return _drawNeighbors(qid);
  }

  /// Warms [qids] in the background so tapping one is instant.
  ///
  /// Fire and forget: nothing here is awaited by the caller, and a failure
  /// only means the tap falls back to fetching on demand.
  void prefetch(Iterable<String> qids) {
    for (final qid in qids) {
      if (!_qid.hasMatch(qid)) continue;
      if (_readyDraws.containsKey(qid) ||
          _prefetching.contains(qid) ||
          _prefetchQueue.contains(qid)) {
        continue;
      }
      _prefetchQueue.add(qid);
    }
    _drainPrefetchQueue();
  }

  /// Drops queued work that is no longer worth doing — the user has moved on
  /// and those satellites are off screen. Work already in flight is allowed
  /// to finish, since its result is still worth caching.
  void cancelPendingPrefetch() => _prefetchQueue.clear();

  /// Whether any warming is still queued or in flight.
  bool get isPrefetching =>
      _prefetching.isNotEmpty || _prefetchQueue.isNotEmpty;

  /// Whether [qid] can be seated instantly from a warmed draw.
  bool hasReadyDraw(String qid) => _readyDraws.containsKey(qid);

  /// Random topics already drawn and waiting, so "new topic" is immediate.
  final List<String> _readyRandom = <String>[];
  bool _warmingRandom = false;

  /// How many random topics to keep in hand.
  static const int randomTopicsWarm = 2;

  /// Takes a pre-drawn random topic, or null if none is ready yet.
  String? takeWarmRandomQid() =>
      _readyRandom.isEmpty ? null : _readyRandom.removeAt(0);

  bool get hasWarmRandomTopic => _readyRandom.isNotEmpty;

  /// Tops up the pool of random topics in the background.
  ///
  /// Only topics that fill every seat are kept, so pressing "new topic" never
  /// lands on a stub — the same standard the foreground path applies, paid
  /// for while the user is reading instead of while they wait.
  void prefetchRandomTopics() {
    if (_warmingRandom || _readyRandom.length >= randomTopicsWarm) return;
    _warmingRandom = true;
    unawaited(_warmRandom());
  }

  Future<void> _warmRandom() async {
    try {
      var attempts = 0;
      while (_readyRandom.length < randomTopicsWarm && attempts < 6) {
        attempts++;
        final qid = await randomStartQid();
        if (_readyRandom.contains(qid)) continue;
        await node(qid);
        final draw = await _drawNeighbors(qid);
        // Unfiltered, insist on a full rosette so a new topic never opens on
        // a stub. Under a filter, a partial result is the expected shape and
        // demanding six would reject everything.
        final enough = isFiltered ? draw.isNotEmpty : draw.length >= seatCount;
        if (!enough) continue;
        _remember(_readyDraws, qid, draw);
        _readyRandom.add(qid);
      }
    } on Object catch (error) {
      // Not fatal — pressing "new topic" falls back to drawing on demand.
      debugPrint('Perihelion: random topic warm failed: $error');
    } finally {
      _warmingRandom = false;
    }
  }

  void _drainPrefetchQueue() {
    while (_prefetching.length < maxConcurrentPrefetch &&
        _prefetchQueue.isNotEmpty) {
      final qid = _prefetchQueue.removeAt(0);
      _prefetching.add(qid);
      unawaited(_warm(qid));
    }
  }

  Future<void> _warm(String qid) async {
    try {
      await node(qid);
      final draw = await _drawNeighbors(qid);
      if (draw.isNotEmpty) {
        _remember(_readyDraws, qid, draw);
      }
    } on Object catch (error) {
      // Not fatal — the tap will fetch on demand. Logged rather than
      // swallowed so a systematic prefetch failure is visible in the console.
      debugPrint('Perihelion: prefetch for $qid failed: $error');
    } finally {
      _prefetching.remove(qid);
      _drainPrefetchQueue();
    }
  }

  /// Inserts into a bounded cache, evicting the oldest entry when full.
  static void _remember<T>(Map<String, T> cache, String key, T value) {
    if (cache.length >= maxCacheEntries && !cache.containsKey(key)) {
      cache.remove(cache.keys.first);
    }
    cache[key] = value;
  }

  Future<List<WikidataNeighbor>> _drawNeighbors(String qid) async {
    final all = await propertiesFor(qid);
    if (all.isEmpty) return const [];

    final preferred = all
        .where((link) => !blockedProperties.contains(link.pid))
        .toList()
      ..shuffle(_random);

    final chosen = <WikidataNeighbor>[];
    final taken = <String>{};
    final clock = Stopwatch()..start();

    // A couple of slices, because one can come back empty when none of its
    // targets have an article of their own. Strictly bounded: chaining a
    // dozen queries is what made a jump look like it had frozen.
    // Each round widens the net: a fresh slice of properties, and a lower bar
    // for how widely known a neighbour has to be. The best-known candidates
    // therefore take seats first, and the obscure ones only fill what is left.
    final tiers = isFiltered ? filteredNotabilityTiers : notabilityTiers;
    final perRound = isFiltered ? filteredPropertiesSampled : propertiesSampled;
    final rounds = isFiltered ? filteredMaxRounds : maxRounds;

    for (var round = 0;
        round < rounds &&
            round < tiers.length &&
            chosen.length < seatCount &&
            clock.elapsed < sampleBudget;
        round++) {
      var slice = preferred
          .skip(round * perRound)
          .take(perRound)
          .toList(growable: false);
      // Once the property list is exhausted, keep going on the first slice
      // with the lower bar rather than stopping early.
      if (slice.isEmpty) {
        slice = preferred.take(perRound).toList(growable: false);
      }
      if (slice.isEmpty) break;
      final rows = await _neighborRows(
        qid,
        slice,
        // Under a filter the text match is doing the selecting, so insisting
        // the neighbour also have its own article is one constraint too many.
        requireArticle: !isFiltered,
        minSitelinks: tiers[round],
      );
      _absorb(rows, qid, chosen, taken);
    }

    // Last resort for a thinly connected topic: drop the requirement that a
    // neighbour have its own article, and let the blocked properties back in.
    // A duller satellite beats an empty seat.
    if (chosen.length < seatCount && clock.elapsed < sampleBudget) {
      final fallback = List<PropertyLink>.of(all)..shuffle(_random);
      final rows = await _neighborRows(
        qid,
        fallback.take(propertiesSampled).toList(growable: false),
        requireArticle: false,
        minSitelinks: 0,
      );
      _absorb(rows, qid, chosen, taken);
    }

    // A stub — a hamlet, a minor species — can genuinely hold fewer than six
    // statements. Step out one hop through a neighbour already on screen.
    // One seed, one query: listing a neighbour's properties can take ten
    // seconds on its own if that neighbour happens to be a country.
    if (chosen.length < seatCount &&
        chosen.isNotEmpty &&
        clock.elapsed < sampleBudget) {
      await _fillFromSecondHop(chosen.first, qid, chosen, taken);
    }

    return chosen.take(seatCount).toList(growable: false);
  }

  Future<void> _fillFromSecondHop(
    WikidataNeighbor seed,
    String centerQid,
    List<WikidataNeighbor> chosen,
    Set<String> taken,
  ) async {
    // Outgoing statements only. The incoming direction is the expensive one,
    // and a stub's neighbour is reached purely to borrow a few extra seats.
    final rows = await _select('''
SELECT ?pd ?dir ?other ?otherLabel ?propLabel ?type WHERE {
  BIND("out" AS ?dir)
  wd:${seed.node.qid} ?pd ?other .
  ?prop wikibase:directClaim ?pd .
  ?sl schema:about ?other ; schema:isPartOf <https://en.wikipedia.org/> .
  OPTIONAL { ?other wdt:P31 ?type }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
LIMIT 60''');

    final staged = <WikidataNeighbor>[];
    _absorb(rows, seed.node.qid, staged, {...taken, centerQid});

    for (final hop in staged) {
      if (chosen.length == seatCount) return;
      if (hop.node.qid == centerQid || taken.contains(hop.node.qid)) continue;
      taken.add(hop.node.qid);
      chosen.add(WikidataNeighbor(
        node: hop.node,
        relation: 'via ${seed.node.label}',
        incoming: false,
      ));
    }
  }

  Future<List<Map<String, dynamic>>> _neighborRows(
    String qid,
    List<PropertyLink> links, {
    required bool requireArticle,
    required int minSitelinks,
  }) async {
    if (links.isEmpty) return const [];

    final fitted = _fitToUrl(links, (candidate) => _buildRowsQuery(
          qid,
          candidate,
          requireArticle: requireArticle,
          minSitelinks: minSitelinks,
        ));

    return _select(_buildRowsQuery(
      qid,
      fitted,
      requireArticle: requireArticle,
      minSitelinks: minSitelinks,
    ));
  }

  String _buildRowsQuery(
    String qid,
    List<PropertyLink> links, {
    required bool requireArticle,
    required int minSitelinks,
  }) {
    final blocks = links.map((link) {
      final pattern = link.incoming
          ? '?other wdt:${link.pid} wd:$qid .'
          : 'wd:$qid wdt:${link.pid} ?other .';
      final tag = '${link.pid}${link.incoming ? 'i' : 'o'}';
      final article = requireArticle
          ? '?sl$tag schema:about ?other ; '
              'schema:isPartOf <https://en.wikipedia.org/> .'
          : 'FILTER(isIRI(?other))';
      final notable = minSitelinks > 0
          ? '?other wikibase:sitelinks ?n$tag . FILTER(?n$tag >= $minSitelinks)'
          : '';
      // Matched inside the subquery, not outside it: filtering after the
      // per-property LIMIT would test ten random candidates and almost
      // always find none.
      final keyword = _keywords.isEmpty
          ? ''
          : '?other rdfs:label ?l$tag . FILTER(lang(?l$tag) = "en") '
              'OPTIONAL { ?other schema:description ?d$tag . '
              'FILTER(lang(?d$tag) = "en") } '
              'BIND(LCASE(CONCAT(?l$tag, " ", COALESCE(?d$tag, ""))) AS ?h$tag) '
              '${_keywords.map((k) => 'FILTER(CONTAINS(?h$tag, "$k"))').join(' ')}';
      return '''
  {
    SELECT ?pd ?dir ?other WHERE {
      BIND(wdt:${link.pid} AS ?pd) BIND("${link.incoming ? 'in' : 'out'}" AS ?dir)
      $pattern
      $article
      $notable
      $keyword
    }
    LIMIT $candidatesPerProperty
  }''';
    }).join('\n  UNION');

    // Stated once over the whole result rather than inside each subquery.
    // Repeating it per property pushed the request URL past 9kB and the
    // endpoint answered 414, which in the app looked like a dead tap.
    final internal = 'FILTER NOT EXISTS { ?other wdt:P31 ?internal . '
        'VALUES ?internal { '
        '${wikimediaInternalTypes.map((q) => 'wd:$q').join(' ')} } }';

    return '''
SELECT ?pd ?dir ?other ?otherLabel ?propLabel ?type WHERE {
$blocks
  ?prop wikibase:directClaim ?pd .
  $internal
  OPTIONAL { ?other wdt:P31 ?type }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
LIMIT 600''';
  }

  /// Adds whatever [rows] can contribute to [chosen], in the three passes
  /// described on [sampleNeighbors].
  void _absorb(
    List<Map<String, dynamic>> rows,
    String centerQid,
    List<WikidataNeighbor> chosen,
    Set<String> taken,
  ) {
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
    if (grouped.isEmpty) return;

    final groups = grouped.values.toList()..shuffle(_random);

    for (final group in groups) {
      if (chosen.length == seatCount) return;
      _take(group, types, chosen, taken, freshCategoryOnly: true);
    }
    for (final group in groups) {
      if (chosen.length == seatCount) return;
      _take(group, types, chosen, taken, freshCategoryOnly: false);
    }
    for (final group in groups) {
      while (chosen.length < seatCount &&
          _take(group, types, chosen, taken, freshCategoryOnly: false)) {
        // Keep drawing from this property until it runs dry.
      }
      if (chosen.length == seatCount) return;
    }
  }

  /// Seats one neighbour from [group] if it can. Returns whether it did.
  bool _take(
    List<Map<String, dynamic>> group,
    Map<String, List<String>> types,
    List<WikidataNeighbor> chosen,
    Set<String> taken, {
    required bool freshCategoryOnly,
  }) {
    final onScreen = chosen.map((n) => n.node.category).toSet();

    final candidates = <Map<String, dynamic>>[];
    for (final row in group) {
      final qid = _localName(_value(row, 'other') ?? '');
      if (taken.contains(qid)) continue;
      final label = _value(row, 'otherLabel');
      // An unlabelled item shows as a bare Q-number, which is not worth a seat.
      if (label == null || label == qid) continue;
      if (freshCategoryOnly) {
        final category = WikidataCategoryMap.forTypes(types[qid] ?? const []);
        if (onScreen.contains(category)) continue;
      }
      candidates.add(row);
    }
    if (candidates.isEmpty) return false;

    final row = candidates[_random.nextInt(candidates.length)];
    final qid = _localName(_value(row, 'other')!);
    taken.add(qid);
    chosen.add(WikidataNeighbor(
      node: WikidataNode(
        qid: qid,
        label: _value(row, 'otherLabel')!,
        description: '',
        category: WikidataCategoryMap.forTypes(types[qid] ?? const []),
      ),
      relation: _value(row, 'propLabel') ?? 'related to',
      incoming: _value(row, 'dir') == 'in',
    ));
    return true;
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

  /// Longest request URL to send.
  ///
  /// The endpoint answers 414 somewhere above nine kilobytes, and a 414 in
  /// the app is indistinguishable from a tap that does nothing. Queries are
  /// trimmed to stay well under it rather than discovering the ceiling in
  /// front of a user.
  static const int maxRequestUrlLength = 7000;

  /// Drops properties from the end until the request will fit.
  static List<PropertyLink> _fitToUrl(
    List<PropertyLink> links,
    String Function(List<PropertyLink>) build,
  ) {
    var fitted = links;
    while (fitted.length > 1 &&
        sparqlUrl(build(fitted)).toString().length > maxRequestUrlLength) {
      fitted = fitted.sublist(0, fitted.length - 1);
    }
    return fitted;
  }

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

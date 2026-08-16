/// A small hand-built graph used by the logic tests, so they do not depend
/// on the content of the shipped asset.
///
/// Shape: `hub` connects to seven nodes across five categories, with two
/// extra `person` nodes so the category-diversity rule has something to fall
/// back on. Returns a fresh mutable structure on every call.
Map<String, dynamic> fakeGraph() => {
      'version': 1,
      'categories': [
        'person',
        'place',
        'work',
        'event',
        'concept',
        'thing',
        'movement',
        'organization',
      ],
      'nodes': [
        _node('hub', 'Hub', 'concept', [
          _edge('p1', 'Employs', 0.90, inverse: 'Employed by'),
          _edge('p2', 'Knows', 0.85, inverse: 'Known by'),
          _edge('p3', 'Taught', 0.80, inverse: 'Taught by'),
          _edge('pl1', 'Sits in', 0.70, inverse: 'Contains'),
          _edge('w1', 'Symmetric with', 0.60),
          _edge('t1', 'Uses', 0.50, inverse: 'Used by'),
          _edge('e1', 'Caused', 0.40, inverse: 'Caused by'),
        ]),
        _node('p1', 'Person One', 'person', [
          _edge('p2', 'Colleague of', 0.55, inverse: 'Colleague of'),
        ]),
        _node('p2', 'Person Two', 'person', []),
        _node('p3', 'Person Three', 'person', []),
        _node('pl1', 'Place One', 'place', [
          // Stated from this end as well; must not double up.
          _edge('p1', 'Home of', 0.65, inverse: 'Lived in'),
        ]),
        _node('w1', 'Work One', 'work', []),
        _node('t1', 'Thing One', 'thing', []),
        _node('e1', 'Event One', 'event', []),
      ],
    };

Map<String, dynamic> _node(
  String id,
  String name,
  String category,
  List<Map<String, dynamic>> edges,
) =>
    {
      'id': id,
      'name': name,
      'category': category,
      'tagline': 'Tagline for $name',
      'summary': 'A summary of $name that is long enough to look like prose '
          'rather than a placeholder string.',
      'facts': [
        {'label': 'Label', 'value': 'Value'},
      ],
      'edges': edges,
    };

Map<String, dynamic> _edge(
  String to,
  String relation,
  double weight, {
  String? inverse,
}) =>
    {
      'to': to,
      'relation': relation,
      'weight': weight,
      'inverse': ?inverse,
    };

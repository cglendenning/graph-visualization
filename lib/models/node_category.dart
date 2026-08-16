import 'package:flutter/material.dart';

/// The eight node types in the graph. Each carries a fixed hue so that a
/// category becomes recognisable at a glance across the whole traversal.
enum NodeCategory {
  person('person', 'PERSON', Color(0xFF56E8FF)),
  place('place', 'PLACE', Color(0xFF2FB6D9)),
  concept('concept', 'CONCEPT', Color(0xFF8AA9FF)),
  work('work', 'WORK', Color(0xFF5FE6C4)),
  thing('thing', 'THING', Color(0xFF33C9A6)),
  event('event', 'EVENT', Color(0xFFFFB259)),
  movement('movement', 'MOVEMENT', Color(0xFFC08CFF)),
  organization('organization', 'ORG', Color(0xFFDCE9F5));

  const NodeCategory(this.id, this.label, this.color);

  final String id;
  final String label;
  final Color color;

  static NodeCategory fromId(String id) {
    for (final c in NodeCategory.values) {
      if (c.id == id) return c;
    }
    throw ArgumentError('Unknown node category: $id');
  }
}

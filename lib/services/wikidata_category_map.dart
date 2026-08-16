import '../models/node_category.dart';

/// Maps a Wikidata "instance of" (P31) value onto one of the eight colours
/// the rosette uses.
///
/// Deliberately small: these few dozen classes cover the overwhelming
/// majority of items a person would browse. Anything unrecognised falls back
/// to [NodeCategory.thing] rather than guessing, so an unmapped class shows
/// up as a neutral node instead of a wrong colour.
class WikidataCategoryMap {
  const WikidataCategoryMap._();

  static const Map<String, NodeCategory> _byType = {
    // person
    'Q5': NodeCategory.person,
    'Q15632617': NodeCategory.person, // fictional human
    'Q95074': NodeCategory.person, // fictional character
    'Q3658341': NodeCategory.person, // literary character

    // place
    'Q515': NodeCategory.place,
    'Q3957': NodeCategory.place, // town
    'Q532': NodeCategory.place, // village
    'Q6256': NodeCategory.place, // country
    'Q486972': NodeCategory.place, // human settlement
    'Q56061': NodeCategory.place, // administrative territorial entity
    'Q82794': NodeCategory.place, // geographic region
    'Q23442': NodeCategory.place, // island
    'Q8502': NodeCategory.place, // mountain
    'Q4022': NodeCategory.place, // river
    'Q23397': NodeCategory.place, // lake
    'Q34763': NodeCategory.place, // peninsula
    'Q1248784': NodeCategory.place, // airport
    'Q41176': NodeCategory.place, // building
    'Q33506': NodeCategory.place, // museum
    'Q3918': NodeCategory.place, // university campus reads as a place
    'Q7275': NodeCategory.place, // state

    // work
    'Q11424': NodeCategory.work, // film
    'Q7725634': NodeCategory.work, // literary work
    'Q571': NodeCategory.work, // book
    'Q49084': NodeCategory.work, // short story
    'Q482994': NodeCategory.work, // album
    'Q134556': NodeCategory.work, // single
    'Q2188189': NodeCategory.work, // musical work
    'Q105543609': NodeCategory.work, // musical work/composition
    'Q3305213': NodeCategory.work, // painting
    'Q860861': NodeCategory.work, // sculpture
    'Q7889': NodeCategory.work, // video game
    'Q5398426': NodeCategory.work, // television series
    'Q25379': NodeCategory.work, // play
    'Q1344': NodeCategory.work, // opera
    'Q13406463': NodeCategory.work, // list article
    'Q191067': NodeCategory.work, // article

    // event
    'Q1656682': NodeCategory.event,
    'Q198': NodeCategory.event, // war
    'Q178561': NodeCategory.event, // battle
    'Q13418847': NodeCategory.event, // historical event
    'Q1190554': NodeCategory.event, // occurrence
    'Q40231': NodeCategory.event, // election
    'Q132241': NodeCategory.event, // festival
    'Q464980': NodeCategory.event, // treaty-ish gathering

    // concept
    'Q151885': NodeCategory.concept,
    'Q11862829': NodeCategory.concept, // academic discipline
    'Q336': NodeCategory.concept, // science
    'Q17737': NodeCategory.concept, // theory
    'Q413': NodeCategory.concept, // physics-like field
    'Q1071': NodeCategory.concept, // field of study
    'Q2623733': NodeCategory.concept, // scientific theory
    'Q7748': NodeCategory.concept, // law
    'Q1156854': NodeCategory.concept, // physical law
    'Q9174': NodeCategory.concept, // religion
    'Q34770': NodeCategory.concept, // language

    // organization
    'Q43229': NodeCategory.organization,
    'Q4830453': NodeCategory.organization, // business
    'Q6881511': NodeCategory.organization, // enterprise
    'Q215380': NodeCategory.organization, // musical group
    'Q7278': NodeCategory.organization, // political party
    'Q31855': NodeCategory.organization, // research institute
    'Q875538': NodeCategory.organization, // public university
    'Q3914': NodeCategory.organization, // school
    'Q327333': NodeCategory.organization, // government agency
    'Q4438121': NodeCategory.organization, // sports organization
    'Q476028': NodeCategory.organization, // football club

    // movement
    'Q968159': NodeCategory.movement, // art movement
    'Q49773': NodeCategory.movement, // social movement
    'Q2198855': NodeCategory.movement, // music genre
    'Q188451': NodeCategory.movement, // music genre (alt)
    'Q201658': NodeCategory.movement, // film genre
    'Q223393': NodeCategory.movement, // literary genre
    'Q1792379': NodeCategory.movement, // art genre
    'Q179805': NodeCategory.movement, // political philosophy

    // thing
    'Q8054': NodeCategory.thing, // protein
    'Q11173': NodeCategory.thing, // chemical compound
    'Q16521': NodeCategory.thing, // taxon
    'Q39546': NodeCategory.thing, // tool
    'Q42889': NodeCategory.thing, // vehicle
    'Q2424752': NodeCategory.thing, // product
    'Q634': NodeCategory.thing, // planet
    'Q523': NodeCategory.thing, // star
    'Q3863': NodeCategory.thing, // asteroid
  };

  /// Resolves the first recognised type among an item's P31 values.
  static NodeCategory forTypes(Iterable<String> typeQids) {
    for (final qid in typeQids) {
      final match = _byType[qid];
      if (match != null) return match;
    }
    return NodeCategory.thing;
  }

  static int get mappedTypeCount => _byType.length;
}

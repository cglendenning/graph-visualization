# Making topics less esoteric — measurements

Taken 19 August 2026 against the live APIs, before any code change.

## The centre is the bigger problem

`generator=random` draws uniformly from ~7M articles, and the encyclopedia
is mostly villages, species, minor athletes and album tracks.

| | random article | most-read pool |
|---|---|---|
| median sitelinks | 2.5 | 47.5 |
| median intro | 281 ch | 1,524 ch |
| has a real paragraph (>=300 ch) | 45% | 80% |
| >=40 sitelinks | 0/20 | 11/20 |

The most-read pool is `wikimedia.org/api/rest_v1/metrics/pageviews/top/`
for a randomly chosen past day. Its tail is varied rather than pure
celebrity: Europe, Advent calendar, Peter III of Russia, Mormon cricket.

Cost: 0.4-0.8s for the day's list, 0.4s for intros and QIDs of 20
candidates in one call. Two requests total.

## Satellite floors

Neighbours above each sitelink floor, sampled per topic:

| topic | total | >=12 | >=25 | >=40 | >=60 | >=80 |
|---|---|---|---|---|---|---|
| Vienna | 641 | 325 | 124 | 72 | 56 | 46 |
| Einstein | 475 | 185 | 132 | 101 | 79 | 64 |
| Artificial intelligence | 745 | 200 | 102 | 61 | 33 | 22 |
| Jazz | 508 | 65 | 35 | 22 | 12 | 8 |
| a small town | 86 | 2 | 2 | 2 | 0 | 0 |

Only six seats are needed, so a first tier of 60 is comfortable even for
Jazz. Thin topics fall through to the unbounded fallback, which is what
keeps the "always six" guarantee intact.

Planned: `notabilityTiers` from `[40, 12, 0]` to `[60, 25, 12]`. The
last-resort fallback stays at 0 so seats are still always filled.

## Verified compatible

Both new endpoints return 200 with the client's existing
`Accept: application/sparql-results+json` header, so no change to the
fetch path is needed.

# Notae Sans — complete family

Notae Sans is a quiet, screen-first neo-grotesk for Notae. It is deliberately conservative, but circular bowls, softened joins, lower visual tension and a compact rhythm make it feel more relaxed than the previous Manrope setup.

The production-candidate family contains upright and genuinely drawn italic styles across a continuous 100–900 weight range.

## Design thesis

**Visual thesis:** calm ink on warm paper; neutral enough for dense work, rounded enough to feel human, and never playful at the expense of reading.

**Content plan:** the specimen tests the complete weight ladder, upright and italic at 12/14/16/18px, mixed-style paragraphs, a realistic Notae interface, glyph coverage and exact load/metric data.

**Interaction thesis:** live weight and size controls, editable copy and light/dark surfaces make the family answer to working typography rather than a static logo.

## Construction and licensing

Notae Sans is a custom-tuned dual-source derivative under the SIL Open Font License 1.1. It is not a trace or copy of Aktiv Grotesk.

- Upright foundation: **Onest**, pinned to `f18c06a14512e43a6191849278d6f07fdaf347d6`.
- Italic foundation: **Inter Italic**, pinned to `353b61b9f4430d5f420d56605a6e7993e0941470`.
- Onest has no italic masters. Using its outlines with a shear would only produce an oblique, so the companion instead begins with Inter's genuinely drawn italic masters: single-storey `a`, redesigned `f` and `g`, cursive joins and dedicated italic spacing across every weight.
- Both sources are renamed throughout as **Notae Sans**, use matching 1,000-unit metrics, expose the same 470 codepoints and carry both upstream copyright notices.
- Core italic alphabetic forms are never mechanically slanted. To close six upstream coverage differences, CR is empty, arrows remain deliberately upright symbols, and the deprecated `ŉ` plus U+030B/U+0312 marks receive a restrained posture adjustment and mark attachment.

The family remains a transparent derivative, not a commissioned from-scratch typeface. Greek and several modern currency signs remain future character-set work.

## Notae tuning

Upright:

- 2% narrower outlines to preserve Notae's existing interface density.
- 1.5% taller outlines for a 535-unit x-height and stronger small-screen reading.
- The approved 300–900 forms remain unchanged; the original Onest interpolation is now restored down through ExtraLight 200 and Thin 100.

Italic:

- 9.4° posture: active enough to read as italic without becoming sharp or literary.
- 4% narrower and vertically matched to a 718-unit cap height.
- 539-unit italic x-height versus 535 upright—a 0.4% difference that keeps small italic counters open.
- Average lowercase advance is 516.8 units versus 517 upright.
- At Regular 400, `H` advances 713 versus 712 upright; `n` 568 versus 579; `o` 576 versus 583.
- Numeral and punctuation widths are retained for clarity, while weight color uses the same calmer 500–850 `avar` progression as upright.

Both styles use typographic ascender 985, descender −315, line gap 0, cap height 718 and consistent macOS, Windows, Linux, iOS, Android and browser line boxes.

## Weight system

| CSS weight | Name | Recommended Notae use |
|---:|---|---|
| 100 | Thin | Very large display type only |
| 200 | ExtraLight | Large editorial headings |
| 300 | Light | Large headings and quiet callouts |
| 400 | Regular | Document body and longer reading |
| 500 | Medium | Dense controls, inputs and metadata |
| 600 | SemiBold | Navigation, labels and buttons |
| 700 | Bold | Section headings and emphasis |
| 800 | ExtraBold | Page and workspace display titles |
| 900 | Black | Rare display accents only |

The variable files support every integer from 100–900, including Notae's intermediate 520, 650, 750, 760 and 850 values.

## Core dimensions

Values are measured from Regular 400 on a 1,000-unit em. “Advance” is horizontal layout width; exact side bearings and visible bounds are in `metrics.json`.

| Glyph | Upright advance | Italic advance |
|---|---:|---:|
| H | 712 | 713 |
| O | 746 | 734 |
| a | 544 | 589 |
| e | 562 | 553 |
| n | 579 | 568 |
| m | 803 | 841 |
| o | 583 | 576 |
| 0 | 652 | 605 |
| 1 | 356 | 391 |
| I | 256 | 258 |
| l | 215 | 232 |
| W | 963 | 946 |
| x | 505 | 524 |

Upright x-height is 535 / 53.5%; italic x-height is 539 / 53.9%; cap height is 718 / 71.8% in both.

## Performance and coverage

- Upright variable WOFF2: 58,756 bytes / 57.4 KB.
- Italic variable WOFF2: 64,348 bytes / 62.8 KB.
- One request per style supplies the entire 100–900 range.
- Both styles expose 470 encoded codepoints: Basic Latin, Latin-1, Latin Extended and Cyrillic.
- The italic retains `ccmp`, `locl`, `calt`, `case`, `pnum`, `tnum`, `kern`, `mark` and `mkmk`, while unrelated source alternate sets are excluded from the web/local family.
- Greek and ₸, ₹, ₺, ₼, ₾ and ₿ are not included in v0.2.

## Build

```sh
python3 -m venv /tmp/notae-sans-venv
/tmp/notae-sans-venv/bin/pip install -r design/type/notae-sans/requirements.txt
/tmp/notae-sans-venv/bin/python design/type/notae-sans/scripts/build_font.py
/tmp/notae-sans-venv/bin/python design/type/notae-sans/scripts/validate_font.py
```

The build fetches and verifies both pinned source commits. Set `NOTAE_ONEST_SOURCE=/path/to/onest` and `NOTAE_INTER_SOURCE=/path/to/inter` to use clean local checkouts at those exact commits.

## Family files

- `fonts/NotaeSans[wght].woff2` — complete upright web family.
- `fonts/NotaeSans-Italic[wght].woff2` — complete italic web family.
- Matching variable TTF files — desktop/PDF-compatible variable fonts.
- `fonts/static/` — nine installable upright and nine installable italic weights in TTF and WOFF2.
- `specimen/index.html` — interactive complete-family specimen.
- `specimen/proofs/italic-pairing.png` — dedicated upright/italic reading proof.
- `metrics.json` — exact axes, vertical metrics, advances, coverage and byte sizes.
- `OFL.txt` — combined source notices and SIL OFL 1.1 text.

## Validation

- Repository validator: 40/40 TTF and WOFF2 binaries pass naming, style linking, 100–900 interpolation, genuine-italic topology, character parity, mark attachment, vertical metrics, transformed-component and round-trip checks.
- FontBakery 1.1.0 variable family: 195 pass / 0 fail / 0 warn (6 info, 41 not-applicable skips).
- FontBakery static family: 1,345 pass / 0 fail / 20 inherited outline-heuristic warnings. Eighteen are contour-count heuristics across the 18 styles; two flag source overlap segments at extreme Black/Thin italic instances. OpenType Sanitizer and visual proofs accept those outlines.
- OpenType Sanitizer 9.2.0 accepts all 40 TTF/WOFF2 binaries.
- HarfBuzz shapes 72 upright/italic × weight × Latin/Cyrillic/numeral samples with no `.notdef` output.
- A second clean build from the two pinned source commits is byte-identical for all 40 binaries.
- Browser proofs cover upright/italic at 12/14/16/18px, mixed paragraphs, desktop/mobile layouts and light/dark surfaces.

## Character-set limitation

The family is ready for Notae's current Latin/Cyrillic product surface. Before using it for Greek-language content or the omitted currency signs, those glyphs should be drawn and reviewed in both upright and italic rather than silently delegated to a fallback.

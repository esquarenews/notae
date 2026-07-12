#!/usr/bin/env python3
"""Build the Notae Sans production-candidate family.

The upright is based on the OFL-licensed Onest family. Onest has no italic
masters, so the genuinely drawn italic companion is based on Inter's OFL
italic source. Both projects are pinned below. The two sets receive matching
Notae proportions, vertical metrics, character coverage, naming and weight
progression. Core alphabetic italic forms are genuinely drawn, not slanted.
"""

from __future__ import annotations

import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
from copy import deepcopy
from pathlib import Path

from fontTools import subset
from fontTools.pens.boundsPen import BoundsPen
from fontTools.otlLib.builder import buildStatTable
from fontTools.ttLib import TTFont, newTable
from fontTools.ttLib.scaleUpem import scale_upem
from fontTools.ttLib.tables._f_v_a_r import NamedInstance
from fontTools.varLib.instancer import instantiateVariableFont


FAMILY = "Notae Sans"
VERSION = "0.200"
UPRIGHT_REPOSITORY = "https://github.com/simpals/onest.git"
UPRIGHT_COMMIT = "f18c06a14512e43a6191849278d6f07fdaf347d6"
ITALIC_REPOSITORY = "https://github.com/rsms/inter.git"
ITALIC_COMMIT = "353b61b9f4430d5f420d56605a6e7993e0941470"
# OpenType timestamps count seconds from 1904-01-01. This is the pinned
# Inter commit time (the newer source), translated from Unix time, so repeated
# builds on different machines are byte-identical.
SOURCE_TIMESTAMP = 1731986170 + 2082844800
WEIGHTS = {
    100: "Thin",
    200: "ExtraLight",
    300: "Light",
    400: "Regular",
    500: "Medium",
    600: "SemiBold",
    700: "Bold",
    800: "ExtraBold",
    900: "Black",
}

ROOT = Path(__file__).resolve().parents[1]
FONT_DIR = ROOT / "fonts"
STATIC_DIR = FONT_DIR / "static"
BUILD_DIR = ROOT / "build"
METRICS_PATH = ROOT / "metrics.json"


def run(*args: str, cwd: Path | None = None) -> None:
    subprocess.run(args, cwd=cwd, check=True)


def source_checkout(
    *,
    label: str,
    repository: str,
    commit: str,
    override_name: str,
    required_path: Path,
) -> Path:
    override = os.environ.get(override_name)
    if override:
        source = Path(override).expanduser().resolve()
        if not (source / required_path).exists():
            raise SystemExit(f"{override_name} is not a {label} checkout: {source}")
        verify_source(source, label=label, commit=commit)
        return source

    source = Path(tempfile.gettempdir()) / "notae-sans-upstream" / label.lower()
    if not source.exists():
        source.parent.mkdir(parents=True, exist_ok=True)
        run("git", "clone", repository, str(source))
    run("git", "fetch", "--depth", "1", "origin", commit, cwd=source)
    run("git", "checkout", "--detach", commit, cwd=source)
    verify_source(source, label=label, commit=commit)
    return source


def verify_source(source: Path, *, label: str, commit: str) -> None:
    try:
        head = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=source, text=True
        ).strip()
        changes = subprocess.check_output(
            ["git", "status", "--porcelain"], cwd=source, text=True
        ).strip()
    except (OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"Unable to verify the pinned Onest checkout: {error}") from error
    if head != commit:
        raise SystemExit(
            f"{label} checkout is at {head}; expected pinned commit {commit}."
        )
    if changes:
        raise SystemExit(f"{label} checkout has local changes; refusing a non-reproducible build.")


def fontmake_executable() -> str:
    sibling = Path(sys.executable).with_name("fontmake")
    if sibling.exists():
        return str(sibling)
    executable = shutil.which("fontmake")
    if executable:
        return executable
    raise SystemExit("fontmake is required. Install design/type/notae-sans/requirements.txt first.")


def fix_nonhinting_executable() -> str:
    sibling = Path(sys.executable).with_name("gftools-fix-nonhinting")
    if sibling.exists():
        return str(sibling)
    executable = shutil.which("gftools-fix-nonhinting")
    if executable:
        return executable
    raise SystemExit(
        "gftools-fix-nonhinting is required. Install "
        "design/type/notae-sans/requirements.txt first."
    )


def set_name(font: TTFont, name_id: int, value: str) -> None:
    names = font["name"]
    names.removeNames(nameID=name_id)
    names.setName(value, name_id, 3, 1, 0x409)


def set_common_names(
    font: TTFont,
    style: str,
    postscript_style: str,
    *,
    legacy_family: str | None = None,
    legacy_style: str | None = None,
    variable: bool = False,
    italic: bool = False,
) -> None:
    legacy_family = legacy_family or FAMILY
    legacy_style = legacy_style or style
    unique_style = ("VariableItalic" if italic else "Variable") if variable else postscript_style
    if variable:
        full_name = f"{FAMILY} Variable{' Italic' if italic else ''}"
    else:
        full_name = f"{FAMILY} {style}"
    if not variable and style == "Regular" and not italic:
        full_name = FAMILY
    set_name(
        font,
        0,
        "Copyright 2021 The Onest Project Authors (https://github.com/googlefonts/onest). "
        "Copyright 2016 The Inter Project Authors (https://github.com/rsms/inter). "
        "Notae family modifications copyright 2026 Notae.",
    )
    set_name(font, 1, legacy_family)
    set_name(font, 2, legacy_style)
    set_name(font, 3, f"{VERSION};NONE;NotaeSans-{unique_style}")
    set_name(font, 4, full_name)
    set_name(font, 5, f"Version {VERSION}; production candidate")
    set_name(font, 6, f"NotaeSans-{unique_style}")
    set_name(
        font,
        8,
        "Onest Project Authors; Inter Project Authors; Notae type adaptation",
    )
    set_name(
        font,
        9,
        "Dmitri Voloshin, Andrey Kudryavtsev, Rasmus Andersson; Notae type adaptation",
    )
    set_name(font, 11, "https://github.com/simpals/onest; https://github.com/rsms/inter")
    set_name(font, 12, "https://github.com/simpals/onest; https://github.com/rsms/inter")
    set_name(
        font,
        13,
        "This Font Software is licensed under the SIL Open Font License, Version 1.1.",
    )
    set_name(font, 14, "https://openfontlicense.org/open-font-license-official-text/")
    set_name(font, 16, FAMILY)
    set_name(font, 17, style)


def add_name(font: TTFont, value: str) -> int:
    return font["name"].addName(
        value,
        platforms=((3, 1, 0x409),),
        minNameID=256,
    )


def remove_legacy_mac_names(font: TTFont) -> None:
    # Current macOS, Windows, Linux, iOS and Android all consume the Unicode
    # platform-3 records. Mac Roman duplicates are obsolete and lossy.
    font["name"].names = [
        record for record in font["name"].names if record.platformID != 1
    ]


def build_variable_instances(font: TTFont, *, italic: bool = False) -> None:
    font["fvar"].instances = []
    for weight, style in WEIGHTS.items():
        instance = NamedInstance()
        display_style = (
            "Italic" if italic and weight == 400 else f"{style} Italic" if italic else style
        )
        instance.subfamilyNameID = add_name(font, display_style)
        if weight == 400:
            postscript_name = "NotaeSans-VariableItalic" if italic else "NotaeSans-Variable"
        else:
            postscript_name = f"NotaeSansVariable-{style}{'Italic' if italic else ''}"
        instance.postscriptNameID = add_name(font, postscript_name)
        instance.coordinates = {"wght": weight}
        font["fvar"].instances.append(instance)


def build_stat(font: TTFont, weights: dict[int, str], *, italic: bool) -> None:
    values = [
        {
            "value": weight,
            "name": style,
            **({"flags": 0x2} if weight == 400 else {}),
        }
        for weight, style in weights.items()
    ]
    buildStatTable(
        font,
        [
            {"tag": "wght", "name": "Weight", "ordering": 0, "values": values},
            {
                "tag": "ital",
                "name": "Italic",
                "ordering": 1,
                "values": [
                    {
                        "value": 1 if italic else 0,
                        "name": "Italic" if italic else "Roman",
                        **({"flags": 0x2} if not italic else {}),
                        **({"linkedValue": 1} if not italic else {}),
                    }
                ],
            },
        ],
        elidedFallbackName="Italic" if italic else "Regular",
    )


def tune_metrics(font: TTFont, *, italic: bool = False) -> None:
    os2 = font["OS/2"]
    hhea = font["hhea"]

    # Outline scale is applied during compilation. These metadata values match
    # the resulting default-master geometry and keep line boxes consistent.
    os2.sxHeight = 539 if italic else 535
    os2.sCapHeight = 718
    os2.sTypoAscender = 985
    os2.sTypoDescender = -315
    os2.sTypoLineGap = 0
    os2.usWinAscent = max(os2.usWinAscent, 1212)
    os2.usWinDescent = max(os2.usWinDescent, 334)
    os2.fsSelection |= 1 << 7  # USE_TYPO_METRICS
    os2.achVendID = "NONE"
    font["head"].fontRevision = float(VERSION)
    hhea.ascent = 985
    hhea.descent = -315
    hhea.lineGap = 0


def normalize_family_metadata(font: TTFont) -> None:
    """Align family metadata that must not vary between style sources."""
    font["OS/2"].panose.bFamilyType = 2
    font["post"].underlinePosition = -75
    font["post"].underlineThickness = 50
    positive_widths = [
        advance for advance, _ in font["hmtx"].metrics.values() if advance > 0
    ]
    font["OS/2"].xAvgCharWidth = round(sum(positive_widths) / len(positive_widths))


def style_variable_font(font: TTFont, *, italic: bool) -> None:
    os2 = font["OS/2"]
    head = font["head"]
    os2.fsSelection &= ~((1 << 0) | (1 << 5) | (1 << 6))
    head.macStyle &= ~((1 << 0) | (1 << 1))
    if italic:
        os2.fsSelection |= 1 << 0
        head.macStyle |= 1 << 1
    else:
        os2.fsSelection |= 1 << 6


def make_legacy_accents_spacing(font: TTFont) -> None:
    # U+0060, U+00B4 and U+02DC are spacing characters, unlike their
    # combining equivalents. The upstream source maps them to zero-width
    # components, which causes Markdown/code punctuation to overprint.
    glyf = font["glyf"]
    cmap = font.getBestCmap()
    widths = {0x0060: 360, 0x00B4: 360, 0x02DC: 520}
    for codepoint, advance in widths.items():
        glyph_name = cmap[codepoint]
        glyph = glyf[glyph_name]
        glyph.recalcBounds(glyf)
        shift = 80 - glyph.xMin
        if not glyph.isComposite():
            raise SystemExit(f"Expected {glyph_name} to be a composite spacing accent.")
        for component in glyph.components:
            component.x += shift
        glyph.recalcBounds(glyf)
        font["hmtx"].metrics[glyph_name] = (advance, 80)


def normalize_timestamp(font: TTFont) -> None:
    font["head"].created = SOURCE_TIMESTAMP
    font["head"].modified = SOURCE_TIMESTAMP


def tune_weight_progression(font: TTFont) -> None:
    # Keep text weights close to familiar UI conventions, then let the family
    # gather weight more gradually between 500 and 850. Endpoints remain valid.
    avar = newTable("avar")
    avar.majorVersion = 1
    avar.minorVersion = 0
    avar.segments = {
        "wght": {
            -1.0: -1.0,
            0.0: 0.0,
            0.2: 0.14,
            0.4: 0.28,
            0.6: 0.46,
            0.8: 0.70,
            0.9: 0.82,
            1.0: 1.0,
        }
    }
    font["avar"] = avar


def write_woff2(font_path: Path, output_path: Path) -> None:
    font = TTFont(font_path, recalcTimestamp=False)
    font.flavor = "woff2"
    font.save(output_path, reorderTables=False)


def style_static_font(font: TTFont, weight: int, style: str, *, italic: bool = False) -> None:
    display_style = f"{style} Italic" if italic else style
    postscript_style = f"{style}{'Italic' if italic else ''}".replace(" ", "")
    is_ribbi = weight in (400, 700)
    set_common_names(
        font,
        display_style,
        postscript_style,
        legacy_family=FAMILY if is_ribbi else f"{FAMILY} {style}",
        legacy_style=(display_style if is_ribbi else ("Italic" if italic else "Regular")),
        italic=italic,
    )
    os2 = font["OS/2"]
    head = font["head"]
    os2.usWeightClass = weight
    os2.fsSelection &= ~((1 << 0) | (1 << 5) | (1 << 6))
    head.macStyle &= ~((1 << 0) | (1 << 1))
    if italic:
        os2.fsSelection |= 1 << 0
        head.macStyle |= 1 << 1
    if weight == 700:
        os2.fsSelection |= 1 << 5
        head.macStyle |= 1
    elif not italic:
        os2.fsSelection |= 1 << 6
    build_stat(font, {weight: style}, italic=italic)
    normalize_family_metadata(font)
    remove_legacy_mac_names(font)


def subset_italic_to_upright(italic: TTFont, upright: TTFont) -> set[int]:
    """Keep the italic web/local set aligned with the upright repertoire.

    Inter lacks six legacy Onest codepoints (CR, deprecated n-apostrophe,
    two rare combining marks and two arrow symbols). All other advertised
    Onest characters—including precomposed Latin Extended and Cyrillic—are
    retained together with the OpenType layout closure they require.
    """
    italic_cmap = set(italic.getBestCmap())
    codepoints = set(upright.getBestCmap()).intersection(italic_cmap)
    # Inter omits explicit empty entries from gvar for non-varying glyphs. The
    # subsetter expects every retained glyph to be keyed, so make those empty
    # entries explicit before calculating layout closure.
    for glyph_name in italic.getGlyphOrder():
        italic["gvar"].variations.setdefault(glyph_name, [])
    options = subset.Options()
    # Match the app-facing feature surface of the upright. Inter's full source
    # also contains eight stylistic sets, fractions, super/subscripts and many
    # character variants; retaining all their closure would add ~40 KB to the
    # webfont without serving Notae's advertised repertoire.
    options.layout_features = [
        "ccmp",
        "locl",
        "calt",
        "case",
        "pnum",
        "tnum",
        "kern",
        "mark",
        "mkmk",
    ]
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    options.name_legacy = True
    options.glyph_names = True
    options.notdef_glyph = True
    options.notdef_outline = True
    options.recommended_glyphs = True
    options.retain_gids = False
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(unicodes=codepoints)
    subsetter.subset(italic)
    return codepoints


def _add_mark_attachment(font: TTFont, glyph_names: list[str]) -> None:
    """Give added top marks the same attachment class as acutecomb."""
    glyph_order = {name: index for index, name in enumerate(font.getGlyphOrder())}
    gpos = font["GPOS"].table
    for lookup in gpos.LookupList.Lookup:
        for subtable in lookup.SubTable:
            if lookup.LookupType == 4 and "acutecomb" in subtable.MarkCoverage.glyphs:
                coverage = subtable.MarkCoverage.glyphs
                records = subtable.MarkArray.MarkRecord
                source = deepcopy(records[coverage.index("acutecomb")])
                mapping = dict(zip(coverage, records, strict=True))
                for glyph_name in glyph_names:
                    record = deepcopy(source)
                    record.MarkAnchor.XCoordinate = 0
                    record.MarkAnchor.YCoordinate = 539
                    mapping[glyph_name] = record
                ordered = sorted(mapping, key=glyph_order.__getitem__)
                subtable.MarkCoverage.glyphs = ordered
                subtable.MarkArray.MarkRecord = [mapping[name] for name in ordered]
                subtable.MarkArray.MarkCount = len(ordered)
            elif lookup.LookupType == 6 and "acutecomb" in subtable.Mark1Coverage.glyphs:
                coverage = subtable.Mark1Coverage.glyphs
                records = subtable.Mark1Array.MarkRecord
                source = deepcopy(records[coverage.index("acutecomb")])
                mapping = dict(zip(coverage, records, strict=True))
                for glyph_name in glyph_names:
                    record = deepcopy(source)
                    record.MarkAnchor.XCoordinate = 0
                    record.MarkAnchor.YCoordinate = 539
                    mapping[glyph_name] = record
                ordered = sorted(mapping, key=glyph_order.__getitem__)
                subtable.Mark1Coverage.glyphs = ordered
                subtable.Mark1Array.MarkRecord = [mapping[name] for name in ordered]
                subtable.Mark1Array.MarkCount = len(ordered)

    gdef = font["GDEF"].table
    if gdef.GlyphClassDef is not None:
        for glyph_name in glyph_names:
            gdef.GlyphClassDef.classDefs[glyph_name] = 3
    mark_sets = getattr(gdef, "MarkGlyphSetsDef", None)
    if mark_sets is not None:
        for coverage in mark_sets.Coverage:
            if "acutecomb" in coverage.glyphs:
                coverage.glyphs = sorted(
                    set(coverage.glyphs).union(glyph_names), key=glyph_order.__getitem__
                )


def add_upright_only_italic_glyphs(italic: TTFont, upright: TTFont) -> None:
    """Close the six-codepoint source gap without changing common italics.

    CR is empty and the arrows are intentionally unslanted symbols. The rare
    deprecated n-apostrophe and two combining marks receive a restrained
    9.4-degree shear so they follow the italic posture. Core alphabetic forms
    remain the genuinely drawn Inter italic designs.
    """
    italic_cmap = italic.getBestCmap()
    upright_cmap = upright.getBestCmap()
    missing = sorted(set(upright_cmap).difference(italic_cmap))
    expected = [0x000D, 0x0149, 0x030B, 0x0312, 0x21B6, 0x21B7]
    if missing != expected:
        raise SystemExit(
            f"Unexpected upright/italic coverage difference: {[hex(cp) for cp in missing]}"
        )

    upright_glyf = upright["glyf"]
    italic_glyf = italic["glyf"]
    order = italic.getGlyphOrder()
    sheared_codepoints = {0x0149, 0x030B, 0x0312}
    shear = math.tan(math.radians(9.4))
    added_mark_names: list[str] = []
    metric_sources = {
        0x000D: ".notdef",
        0x0149: "n",
        0x030B: "acutecomb",
        0x0312: "acutecomb",
        0x21B6: italic_cmap[0x2190],
        0x21B7: italic_cmap[0x2192],
    }

    for codepoint in missing:
        glyph_name = upright_cmap[codepoint]
        if glyph_name in italic_glyf.glyphs:
            raise SystemExit(f"Cannot add {glyph_name}; the italic already uses that glyph name.")
        glyph = deepcopy(upright_glyf[glyph_name])
        italic_glyf.glyphs[glyph_name] = glyph
        order.append(glyph_name)
        italic["hmtx"].metrics[glyph_name] = upright["hmtx"].metrics[glyph_name]
        italic["gvar"].variations[glyph_name] = deepcopy(
            upright["gvar"].variations.get(glyph_name, [])
        )
        hvar_map = italic["HVAR"].table.AdvWidthMap.mapping
        hvar_map[glyph_name] = hvar_map[metric_sources[codepoint]]

        if codepoint in sheared_codepoints:
            coordinates, _, _ = glyph.getCoordinates(italic_glyf)
            for index, (x, y) in enumerate(coordinates):
                coordinates[index] = (round(x + y * shear), y)
            for variation in italic["gvar"].variations[glyph_name]:
                variation.coordinates = [
                    None
                    if point is None
                    else (round(point[0] + point[1] * shear), point[1])
                    for point in variation.coordinates
                ]
            glyph.recalcBounds(italic_glyf)
            advance, _ = italic["hmtx"].metrics[glyph_name]
            if advance:
                advance = max(advance, glyph.xMax + 40)
            italic["hmtx"].metrics[glyph_name] = (advance, glyph.xMin)

        if codepoint in (0x030B, 0x0312):
            added_mark_names.append(glyph_name)

        for cmap_table in italic["cmap"].tables:
            if cmap_table.isUnicode() and hasattr(cmap_table, "cmap"):
                cmap_table.cmap[codepoint] = glyph_name

    italic.setGlyphOrder(order)
    italic["maxp"].numGlyphs = len(order)
    _add_mark_attachment(italic, added_mark_names)


def glyph_metrics(font: TTFont, character: str) -> dict[str, int | str | None]:
    glyph_name = font.getBestCmap().get(ord(character))
    if not glyph_name:
        return {"glyph": None, "advance": None, "left_side_bearing": None, "box": None}
    advance, left_side_bearing = font["hmtx"].metrics[glyph_name]
    glyph_set = font.getGlyphSet()
    pen = BoundsPen(glyph_set)
    glyph_set[glyph_name].draw(pen)
    return {
        "glyph": glyph_name,
        "advance": advance,
        "left_side_bearing": left_side_bearing,
        "box": list(pen.bounds) if pen.bounds else None,
    }


def write_metrics(
    variable_ttf: Path,
    variable_woff2: Path,
    italic_ttf: Path,
    italic_woff2: Path,
) -> None:
    variable = TTFont(variable_ttf)
    regular = instantiateVariableFont(variable, {"wght": 400}, inplace=False, optimize=True)
    italic_variable = TTFont(italic_ttf)
    italic_regular = instantiateVariableFont(
        italic_variable, {"wght": 400}, inplace=False, optimize=True
    )
    cmap = regular.getBestCmap()
    os2 = regular["OS/2"]
    head = regular["head"]
    widths = {
        character: glyph_metrics(regular, character)
        for character in ["H", "O", "a", "e", "n", "m", "o", "0", "1", "I", "l", "W", "x"]
    }
    lowercase_advances = [
        regular["hmtx"].metrics[cmap[codepoint]][0]
        for codepoint in range(ord("a"), ord("z") + 1)
        if codepoint in cmap
    ]
    italic_cmap = italic_regular.getBestCmap()
    italic_widths = {
        character: glyph_metrics(italic_regular, character)
        for character in ["H", "O", "a", "e", "n", "m", "o", "0", "1", "I", "l", "W", "x", "f", "g"]
    }
    italic_lowercase_advances = [
        italic_regular["hmtx"].metrics[italic_cmap[codepoint]][0]
        for codepoint in range(ord("a"), ord("z") + 1)
        if codepoint in italic_cmap
    ]
    missing_italic_codepoints = sorted(set(cmap).difference(italic_cmap))
    metrics = {
        "family": FAMILY,
        "version": VERSION,
        "status": "production candidate; built for Notae integration",
        "source": {
            "upright": {
                "family": "Onest",
                "repository": UPRIGHT_REPOSITORY,
                "commit": UPRIGHT_COMMIT,
            },
            "italic": {
                "family": "Inter Italic",
                "repository": ITALIC_REPOSITORY,
                "commit": ITALIC_COMMIT,
                "construction": (
                    "genuinely drawn alphabetic italic masters; three rare supplemental "
                    "codepoints optically adapted for coverage parity"
                ),
            },
            "license": "SIL Open Font License 1.1",
        },
        "design_tuning": {
            "upright_horizontal_outline_scale_percent": 98.0,
            "upright_vertical_outline_scale_percent": 101.5,
            "italic_horizontal_outline_scale_percent": 96.0,
            "italic_vertical_outline_scale_percent": 98.7,
            "italic_angle_degrees": italic_regular["post"].italicAngle,
            "weight_progression": "calmer 500–850 progression via avar",
            "default_shapes": "double-storey a retained; Onest readability alternates remain available",
        },
        "axis": {"tag": "wght", "minimum": 100, "default": 400, "maximum": 900},
        "named_weights": WEIGHTS,
        "vertical_metrics": {
            "units_per_em": head.unitsPerEm,
            "x_height": os2.sxHeight,
            "cap_height": os2.sCapHeight,
            "typo_ascender": os2.sTypoAscender,
            "typo_descender": os2.sTypoDescender,
            "typo_line_gap": os2.sTypoLineGap,
            "win_ascent": os2.usWinAscent,
            "win_descent": os2.usWinDescent,
        },
        "regular_400_glyph_metrics": widths,
        "italic_400_glyph_metrics": italic_widths,
        "regular_400_spacing_accents": {
            character: glyph_metrics(regular, character)
            for character in ["`", "´", "˜"]
        },
        "regular_400_average_lowercase_advance": round(sum(lowercase_advances) / len(lowercase_advances), 1),
        "italic_400_average_lowercase_advance": round(
            sum(italic_lowercase_advances) / len(italic_lowercase_advances), 1
        ),
        "coverage": {
            "upright_glyph_count": len(regular.getGlyphOrder()),
            "upright_encoded_codepoints": len(cmap),
            "italic_glyph_count": len(italic_regular.getGlyphOrder()),
            "italic_encoded_codepoints": len(italic_cmap),
            "italic_missing_from_upright": [
                f"U+{codepoint:04X}" for codepoint in missing_italic_codepoints
            ],
            "basic_latin": sum(0x0020 <= codepoint <= 0x007E for codepoint in cmap),
            "latin_1_supplement": sum(0x00A0 <= codepoint <= 0x00FF for codepoint in cmap),
            "latin_extended": sum(0x0100 <= codepoint <= 0x024F for codepoint in cmap),
            "cyrillic": sum(0x0400 <= codepoint <= 0x052F for codepoint in cmap),
        },
        "files": {
            variable_ttf.name: variable_ttf.stat().st_size,
            variable_woff2.name: variable_woff2.stat().st_size,
            italic_ttf.name: italic_ttf.stat().st_size,
            italic_woff2.name: italic_woff2.stat().st_size,
        },
    }
    METRICS_PATH.write_text(json.dumps(metrics, indent=2, sort_keys=True) + "\n")


def main() -> None:
    upright_source = source_checkout(
        label="Onest",
        repository=UPRIGHT_REPOSITORY,
        commit=UPRIGHT_COMMIT,
        override_name="NOTAE_ONEST_SOURCE",
        required_path=Path("sources/Onest.glyphs"),
    )
    italic_source = source_checkout(
        label="Inter",
        repository=ITALIC_REPOSITORY,
        commit=ITALIC_COMMIT,
        override_name="NOTAE_INTER_SOURCE",
        required_path=Path("src/Inter-Italic.glyphspackage"),
    )
    FONT_DIR.mkdir(parents=True, exist_ok=True)
    STATIC_DIR.mkdir(parents=True, exist_ok=True)
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    for old_font in STATIC_DIR.glob("NotaeSans-*"):
        old_font.unlink()

    raw_path = BUILD_DIR / "NotaeSans-raw.ttf"
    variable_ttf = FONT_DIR / "NotaeSans[wght].ttf"
    variable_woff2 = FONT_DIR / "NotaeSans[wght].woff2"
    run(
        fontmake_executable(),
        "-g",
        str(upright_source / "sources" / "Onest.glyphs"),
        "-o",
        "variable",
        "--family-name",
        FAMILY,
        "--output-path",
        str(raw_path),
        "--filter",
        "TransformationsFilter(ScaleX=98,ScaleY=101.5)",
        "--filter",
        "DecomposeTransformedComponentsFilter",
        "--master-dir",
        "{tmp}",
        "--no-autohint",
        "--verbose",
        "WARNING",
        cwd=upright_source,
    )

    variable = TTFont(raw_path, recalcBBoxes=True, recalcTimestamp=False)
    variable = instantiateVariableFont(
        variable,
        {"wght": (100, 400, 900)},
        inplace=False,
        optimize=True,
    )
    set_common_names(
        variable,
        "Regular",
        "Regular",
        legacy_family=f"{FAMILY} Variable",
        legacy_style="Regular",
        variable=True,
    )
    set_name(variable, 25, "NotaeSans")
    tune_metrics(variable)
    style_variable_font(variable, italic=False)
    make_legacy_accents_spacing(variable)
    tune_weight_progression(variable)
    build_variable_instances(variable)
    build_stat(variable, WEIGHTS, italic=False)
    normalize_family_metadata(variable)
    remove_legacy_mac_names(variable)
    normalize_timestamp(variable)
    pre_nonhinting = BUILD_DIR / "NotaeSans-pre-nonhinting.ttf"
    variable.save(pre_nonhinting, reorderTables=False)
    run(
        fix_nonhinting_executable(),
        "--no-backup",
        "-q",
        str(pre_nonhinting),
        str(variable_ttf),
    )
    variable = TTFont(variable_ttf, recalcTimestamp=False)
    normalize_timestamp(variable)
    variable.save(variable_ttf, reorderTables=False)
    write_woff2(variable_ttf, variable_woff2)

    for weight, style in WEIGHTS.items():
        instance = TTFont(variable_ttf, recalcTimestamp=False)
        instance = instantiateVariableFont(instance, {"wght": weight}, inplace=False, optimize=True)
        style_static_font(instance, weight, style)
        normalize_timestamp(instance)
        ttf_path = STATIC_DIR / f"NotaeSans-{style}.ttf"
        woff2_path = STATIC_DIR / f"NotaeSans-{style}.woff2"
        instance.save(ttf_path, reorderTables=False)
        write_woff2(ttf_path, woff2_path)

    italic_raw_path = BUILD_DIR / "NotaeSans-Italic-raw.ttf"
    italic_ttf = FONT_DIR / "NotaeSans-Italic[wght].ttf"
    italic_woff2 = FONT_DIR / "NotaeSans-Italic[wght].woff2"
    run(
        fontmake_executable(),
        "-g",
        str(italic_source / "src" / "Inter-Italic.glyphspackage"),
        "-o",
        "variable",
        "--family-name",
        FAMILY,
        "--output-path",
        str(italic_raw_path),
        "--filter",
        "TransformationsFilter(ScaleX=96,ScaleY=98.7)",
        "--filter",
        "DecomposeTransformedComponentsFilter",
        "--filter",
        "FlattenComponentsFilter",
        "--master-dir",
        "{tmp}",
        "--no-autohint",
        "--verbose",
        "WARNING",
        cwd=italic_source,
    )
    italic = TTFont(italic_raw_path, recalcBBoxes=True, recalcTimestamp=False)
    italic = instantiateVariableFont(
        italic,
        {"opsz": 14, "wght": (100, 400, 900)},
        inplace=False,
        optimize=True,
    )
    scale_upem(italic, 1000)
    upright_for_coverage = TTFont(variable_ttf, recalcTimestamp=False)
    subset_italic_to_upright(italic, upright_for_coverage)
    add_upright_only_italic_glyphs(italic, upright_for_coverage)
    set_common_names(
        italic,
        "Italic",
        "Italic",
        legacy_family=f"{FAMILY} Variable",
        legacy_style="Italic",
        variable=True,
        italic=True,
    )
    set_name(italic, 25, "NotaeSansItalic")
    tune_metrics(italic, italic=True)
    style_variable_font(italic, italic=True)
    tune_weight_progression(italic)
    build_variable_instances(italic, italic=True)
    build_stat(italic, WEIGHTS, italic=True)
    normalize_family_metadata(italic)
    remove_legacy_mac_names(italic)
    normalize_timestamp(italic)
    italic_pre_nonhinting = BUILD_DIR / "NotaeSans-Italic-pre-nonhinting.ttf"
    italic.save(italic_pre_nonhinting, reorderTables=False)
    run(
        fix_nonhinting_executable(),
        "--no-backup",
        "-q",
        str(italic_pre_nonhinting),
        str(italic_ttf),
    )
    italic = TTFont(italic_ttf, recalcTimestamp=False)
    normalize_timestamp(italic)
    italic.save(italic_ttf, reorderTables=False)
    write_woff2(italic_ttf, italic_woff2)

    for weight, style in WEIGHTS.items():
        instance = TTFont(italic_ttf, recalcTimestamp=False)
        instance = instantiateVariableFont(instance, {"wght": weight}, inplace=False, optimize=True)
        style_static_font(instance, weight, style, italic=True)
        normalize_timestamp(instance)
        ttf_path = STATIC_DIR / f"NotaeSans-{style}Italic.ttf"
        woff2_path = STATIC_DIR / f"NotaeSans-{style}Italic.woff2"
        instance.save(ttf_path, reorderTables=False)
        write_woff2(ttf_path, woff2_path)

    onest_license = (upright_source / "OFL.txt").read_text()
    license_body = onest_license[onest_license.index("-----------------------------------------------------------"):]
    (ROOT / "OFL.txt").write_text(
        "Copyright 2021 The Onest Project Authors (https://github.com/googlefonts/onest)\n"
        "Copyright (c) 2016 The Inter Project Authors (https://github.com/rsms/inter)\n"
        "Notae family modifications copyright 2026 Notae.\n\n"
        "This Font Software is licensed under the SIL Open Font License, Version 1.1.\n"
        "The full license follows.\n\n"
        + license_body
    )
    write_metrics(variable_ttf, variable_woff2, italic_ttf, italic_woff2)
    raw_path.unlink(missing_ok=True)
    pre_nonhinting.unlink(missing_ok=True)
    italic_raw_path.unlink(missing_ok=True)
    italic_pre_nonhinting.unlink(missing_ok=True)
    print(f"Built {variable_ttf}")
    print(f"Built {variable_woff2}")
    print(f"Built {italic_ttf}")
    print(f"Built {italic_woff2}")
    print(f"Wrote {METRICS_PATH}")


if __name__ == "__main__":
    main()

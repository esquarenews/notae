#!/usr/bin/env python3
"""Validate every Notae Sans font and its published technical claims."""

from __future__ import annotations

import json
import tempfile
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont


ROOT = Path(__file__).resolve().parents[1]
FONT_DIR = ROOT / "fonts"
STATIC_DIR = FONT_DIR / "static"
METRICS_PATH = ROOT / "metrics.json"
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
IDENTITY_NAME_IDS = {1, 2, 3, 4, 6, 16, 17, 25}
REQUIRED_CHARACTERS = (
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "abcdefghijklmnopqrstuvwxyz"
    "0123456789"
    "ÀéñøŒß€£¥₽₴"
    "АбвЯяЁё"
)


def names(font: TTFont, name_id: int) -> set[str]:
    return {
        record.toUnicode()
        for record in font["name"].names
        if record.nameID == name_id
    }


def assert_identity(
    font: TTFont,
    expected_style: str,
    *,
    legacy_family: str = "Notae Sans",
    legacy_style: str | None = None,
) -> None:
    assert names(font, 1) == {legacy_family}
    assert names(font, 2) == {legacy_style or expected_style}
    assert names(font, 16) == {"Notae Sans"}
    assert names(font, 17) == {expected_style}
    assert not any(record.platformID == 1 for record in font["name"].names)
    for record in font["name"].names:
        if record.nameID in IDENTITY_NAME_IDS:
            value = record.toUnicode()
            assert "Onest" not in value and "Inter" not in value


def stat_values(font: TTFont) -> list:
    values = font["STAT"].table.AxisValueArray
    return [] if values is None else values.AxisValue


def assert_no_transformed_components(font: TTFont) -> None:
    glyf = font["glyf"]
    for glyph_name in font.getGlyphOrder():
        glyph = glyf[glyph_name]
        if not glyph.isComposite():
            continue
        for component in glyph.components:
            transform = component.getComponentInfo()[1]
            assert transform[:4] == (1, 0, 0, 1), (glyph_name, transform)


def assert_no_nested_components(font: TTFont) -> None:
    glyf = font["glyf"]
    for glyph_name in font.getGlyphOrder():
        glyph = glyf[glyph_name]
        if not glyph.isComposite():
            continue
        assert all(
            not glyf[component.glyphName].isComposite()
            for component in glyph.components
        ), glyph_name


def assert_family_metadata(font: TTFont) -> None:
    assert font["OS/2"].panose.bFamilyType == 2
    assert font["post"].underlinePosition == -75
    assert font["post"].underlineThickness == 50
    positive_widths = [
        advance for advance, _ in font["hmtx"].metrics.values() if advance > 0
    ]
    assert font["OS/2"].xAvgCharWidth == round(
        sum(positive_widths) / len(positive_widths)
    )


def assert_round_trip(path: Path) -> None:
    font = TTFont(path, recalcTimestamp=False)
    with tempfile.NamedTemporaryFile(suffix=path.suffix) as output:
        font.save(output.name, reorderTables=False)
        TTFont(output.name, recalcTimestamp=False).getGlyphOrder()


def assert_style_bits(font: TTFont, *, italic: bool, bold: bool, regular: bool) -> None:
    selection = font["OS/2"].fsSelection
    mac_style = font["head"].macStyle
    assert bool(selection & (1 << 0)) == italic
    assert bool(selection & (1 << 5)) == bold
    assert bool(selection & (1 << 6)) == regular
    assert bool(mac_style & (1 << 0)) == bold
    assert bool(mac_style & (1 << 1)) == italic


def validate_variable(metrics: dict, *, italic: bool) -> None:
    stem = "NotaeSans-Italic[wght]" if italic else "NotaeSans[wght]"
    expected_style = "Italic" if italic else "Regular"
    for suffix in ("ttf", "woff2"):
        path = FONT_DIR / f"{stem}.{suffix}"
        font = TTFont(path, recalcTimestamp=False)
        assert_identity(
            font,
            expected_style,
            legacy_family="Notae Sans Variable",
            legacy_style=expected_style,
        )
        assert "fvar" in font and "avar" in font and "gvar" in font
        assert "GPOS" in font and "GSUB" in font
        feature_tags = {
            record.FeatureTag for record in font["GPOS"].table.FeatureList.FeatureRecord
        }
        assert "kern" in feature_tags
        axes = {axis.axisTag: axis for axis in font["fvar"].axes}
        assert set(axes) == {"wght"}
        weight = axes["wght"]
        assert (weight.minValue, weight.defaultValue, weight.maxValue) == (100, 400, 900)
        assert font["head"].unitsPerEm == 1000
        assert font["OS/2"].sxHeight == (539 if italic else 535)
        assert font["OS/2"].sCapHeight == 718
        assert font["OS/2"].fsSelection & (1 << 7)
        assert font["OS/2"].achVendID == "NONE"
        assert abs(font["head"].fontRevision - 0.2) < 0.0001
        assert_style_bits(font, italic=italic, bold=False, regular=not italic)
        if italic:
            assert -10.0 < font["post"].italicAngle < -9.0
        else:
            assert font["post"].italicAngle == 0
        assert "prep" in font and "gasp" in font
        cmap = font.getBestCmap()
        assert all(ord(character) in cmap for character in REQUIRED_CHARACTERS)
        instances = {
            int(instance.coordinates["wght"]): next(
                iter(names(font, instance.subfamilyNameID))
            )
            for instance in font["fvar"].instances
        }
        assert instances == {
            weight: (
                "Italic"
                if italic and weight == 400
                else f"{style} Italic"
                if italic
                else style
            )
            for weight, style in WEIGHTS.items()
        }
        regular_instance = next(
            instance
            for instance in font["fvar"].instances
            if int(instance.coordinates["wght"]) == 400
        )
        assert names(font, regular_instance.postscriptNameID) == names(font, 6)
        assert [axis.AxisTag for axis in font["STAT"].table.DesignAxisRecord.Axis] == [
            "wght",
            "ital",
        ]
        assert len(stat_values(font)) == len(WEIGHTS) + 1
        assert_no_transformed_components(font)
        assert_no_nested_components(font)
        assert_family_metadata(font)
        assert_round_trip(path)

    size_limit = 70 * 1024 if italic else 64 * 1024
    assert (FONT_DIR / f"{stem}.woff2").stat().st_size < size_limit
    coverage_key = "italic_glyph_count" if italic else "upright_glyph_count"
    for weight in [*WEIGHTS, 520, 650, 750, 760, 850]:
        source = TTFont(FONT_DIR / f"{stem}.ttf", recalcTimestamp=False)
        instance = instantiateVariableFont(
            source, {"wght": weight}, inplace=False, optimize=True
        )
        assert "fvar" not in instance
        assert len(instance.getGlyphOrder()) == metrics["coverage"][coverage_key]
        for character in "`´˜":
            glyph_name = instance.getBestCmap()[ord(character)]
            advance, _ = instance["hmtx"].metrics[glyph_name]
            assert advance > 0


def validate_true_italic() -> None:
    upright = TTFont(FONT_DIR / "NotaeSans[wght].ttf", recalcTimestamp=False)
    italic = TTFont(FONT_DIR / "NotaeSans-Italic[wght].ttf", recalcTimestamp=False)
    upright = instantiateVariableFont(upright, {"wght": 400}, inplace=False)
    italic = instantiateVariableFont(italic, {"wght": 400}, inplace=False)
    # A synthetic slant preserves contour topology. The companion's genuinely
    # drawn single-storey italic a and reshaped f/g have different topology.
    for character in "afg":
        upright_glyph = upright["glyf"][upright.getBestCmap()[ord(character)]]
        italic_glyph = italic["glyf"][italic.getBestCmap()[ord(character)]]
        assert (
            upright_glyph.numberOfContours,
            len(upright_glyph.getCoordinates(upright["glyf"])[0]),
        ) != (
            italic_glyph.numberOfContours,
            len(italic_glyph.getCoordinates(italic["glyf"])[0]),
        )


def validate_statics() -> None:
    variables = [
        TTFont(FONT_DIR / "NotaeSans[wght].ttf", recalcTimestamp=False),
        TTFont(FONT_DIR / "NotaeSans-Italic[wght].ttf", recalcTimestamp=False),
    ]
    variable_install_names = {
        next(iter(names(variable, name_id)))
        for variable in variables
        for name_id in (3, 4, 6)
    }
    for italic in (False, True):
        for weight, style in WEIGHTS.items():
            display_style = f"{style} Italic" if italic else style
            suffix_name = f"{style}{'Italic' if italic else ''}"
            for suffix in ("ttf", "woff2"):
                path = STATIC_DIR / f"NotaeSans-{suffix_name}.{suffix}"
                font = TTFont(path, recalcTimestamp=False)
                is_ribbi = weight in (400, 700)
                assert_identity(
                    font,
                    display_style,
                    legacy_family=(
                        "Notae Sans" if is_ribbi else f"Notae Sans {style}"
                    ),
                    legacy_style=(
                        display_style
                        if is_ribbi
                        else ("Italic" if italic else "Regular")
                    ),
                )
                assert "fvar" not in font and "gvar" not in font
                assert font["OS/2"].usWeightClass == weight
                assert_style_bits(
                    font,
                    italic=italic,
                    bold=weight == 700,
                    regular=(not italic and weight != 700),
                )
                assert font["OS/2"].achVendID == "NONE"
                assert abs(font["head"].fontRevision - 0.2) < 0.0001
                assert "prep" in font and "gasp" in font
                assert len(stat_values(font)) == 2
                assert_no_transformed_components(font)
                assert_no_nested_components(font)
                assert_family_metadata(font)
                assert not variable_install_names.intersection(
                    next(iter(names(font, name_id))) for name_id in (3, 4, 6)
                )
                assert_round_trip(path)


def validate_metrics(metrics: dict) -> None:
    assert metrics["status"] == "production candidate; built for Notae integration"
    assert metrics["axis"] == {
        "tag": "wght",
        "minimum": 100,
        "default": 400,
        "maximum": 900,
    }
    assert "local_checkout" not in metrics["source"]
    assert metrics["coverage"]["upright_glyph_count"] == 534
    assert metrics["coverage"]["upright_encoded_codepoints"] == 470
    assert metrics["coverage"]["italic_encoded_codepoints"] == 470
    assert metrics["coverage"]["italic_missing_from_upright"] == []
    for filename, expected_size in metrics["files"].items():
        assert (FONT_DIR / filename).stat().st_size == expected_size


def main() -> None:
    metrics = json.loads(METRICS_PATH.read_text())
    validate_variable(metrics, italic=False)
    validate_variable(metrics, italic=True)
    validate_true_italic()
    validate_statics()
    validate_metrics(metrics)
    print(
        "Validated 40 font files, nine named weights in upright and true italic, "
        "and the metrics manifest."
    )


if __name__ == "__main__":
    main()

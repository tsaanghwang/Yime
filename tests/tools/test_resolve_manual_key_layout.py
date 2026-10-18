import json
from pathlib import Path

from tools.resolve_manual_key_layout import validate_layers

ROOT = Path(__file__).resolve().parents[2]


def _entry(*, display_label: str, literal_char: str | None) -> dict[str, object]:
    return {
        "order": 1,
        "physical_key": "q",
        "output_layer": "shift",
        "display_label": display_label,
        "yinyuan_id": None,
        "literal_char": literal_char,
    }


def test_validate_layers_accepts_native_literal() -> None:
    resolved = validate_layers([_entry(display_label="Q", literal_char="Q")], {})

    assert resolved[0]["resolved_char"] == "Q"


def test_validate_layers_rejects_relocated_literal() -> None:
    try:
        validate_layers([_entry(display_label="Q", literal_char="1")], {})
    except ValueError as exc:
        assert "Relocated literal_char is not allowed" in str(exc)
    else:
        raise AssertionError("relocated literal_char should be rejected")


def test_repo_layout_has_no_relocated_literals() -> None:
    layout = json.loads(
        (ROOT / "internal_data" / "manual_key_layout.json").read_text(encoding="utf-8")
    )

    for entry in layout["layers"]:
        literal_char = entry.get("literal_char")
        if literal_char is None:
            continue
        native_literal = " " if entry["physical_key"] == "space" else entry["display_label"]
        assert literal_char == native_literal

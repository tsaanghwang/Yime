from pathlib import Path

from tools.final_classifier import FinalsClassifier
from tools.final_components import FinalsComponentsAnalyzer


ROOT = Path(__file__).resolve().parents[2]


def test_final_classifier_keeps_all_42_instantiated_finals(tmp_path: Path) -> None:
    classifier = FinalsClassifier(
        input_file=str(ROOT / "external_data" / "finals_IPA_mapping.json"),
        output_file=str(tmp_path / "classified_finals.json"),
    )
    classifier.load_data()
    classifier.classify()

    classified = [
        item["拼音"]
        for category in classifier.classified.values()
        for item in category
    ]
    assert len(classified) == 42
    assert set(classified) == set(classifier.data)


def test_component_analyzer_accepts_unicode_combining_marks_from_master() -> None:
    analyzer = FinalsComponentsAnalyzer()
    analyzer.input_file = str(ROOT / "external_data" / "finals_IPA_mapping.json")
    analyzer.analyze_components()

    assert analyzer.extract_components("iɘ̠̆ŋ") == ["i", "ɘ̠̆", "ŋ"]
    missing, _ = analyzer.validate_components()
    assert missing == []

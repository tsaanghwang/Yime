from __future__ import annotations

from yime.input_model.particle_constructions import (
    ParticleSystem,
    classify_particle_constructions,
    review_particle_construction,
)
from yime.utils.lexicon_quality import PARTICLE_SUFFIX_PINYIN


def _ids(text: str, reading: str) -> set[str]:
    return {
        item.construction_id
        for item in classify_particle_constructions(text, reading)
    }


def test_structural_particles_have_distinct_typed_interfaces() -> None:
    de = classify_particle_constructions("红色的", "hong2 se4 de5")
    di = classify_particle_constructions("慢慢地", "man4 man4 de5")
    de_complement = classify_particle_constructions("跑得", "pao3 de5")

    assert de[0].system is ParticleSystem.STRUCTURAL
    assert de[0].interface == "nominal_or_attributive_right_edge"
    assert di[0].interface == "requires_right_predicate"
    assert de_complement[0].interface == "requires_right_complement"


def test_aspectual_and_modal_le_are_preserved_as_parallel_analyses() -> None:
    evidence = classify_particle_constructions("天黑了", "tian1 hei1 le5")
    assert {item.construction_id for item in evidence} == {
        "perfective_le",
        "change_of_state_le",
    }
    review = review_particle_construction("天黑了", "tian1 hei1 le5")
    assert review.suggested_role == "polyfunctional_particle_candidate"


def test_zhe_le_guo_form_an_aspectual_system() -> None:
    assert _ids("看着", "kan4 zhe5") == {"durative_zhe"}
    assert "perfective_le" in _ids("吃了", "chi1 le5")
    assert _ids("见过", "jian4 guo4") == {"experiential_guo"}


def test_reading_gate_excludes_lexical_homographs() -> None:
    assert not classify_particle_constructions("目的", "mu4 di4")
    assert not classify_particle_constructions("土地", "tu3 di4")
    assert not classify_particle_constructions("取得", "qu3 de2")
    assert not classify_particle_constructions("着火", "zhao2 huo3")
    assert not classify_particle_constructions("终了", "zhong1 liao3")


def test_typed_evidence_supports_role_review_without_static_admission() -> None:
    review = review_particle_construction("慢慢地", "man4 man4 de5")
    assert review.suggested_role == "structural_component_candidate"
    assert review.interfaces == ("requires_right_predicate",)
    assert "稳定语法接口" in review.theoretical_basis

    long_review = review_particle_construction(
        "大家慢慢地",
        "da4 jia1 man4 man4 de5",
    )
    assert long_review.suggested_role == "dynamic_sentence_candidate"


def test_policy_covers_every_registered_particle_suffix_reading() -> None:
    for marker, readings in PARTICLE_SUFFIX_PINYIN.items():
        for reading in readings:
            evidence = classify_particle_constructions(
                f"看{marker}",
                f"kan4 {reading}",
            )
            assert evidence, (marker, reading)

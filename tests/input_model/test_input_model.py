from __future__ import annotations

import sqlite3
from pathlib import Path

import pytest

from yime.input_model import (
    CandidateAssessment,
    CandidateClass,
    CompositionPolicy,
    ContextEvidence,
    DecisionStatus,
    DynamicComposer,
    InputModelStore,
    IntegrationPolicy,
    SourceLexicon,
    build_input_model,
)


ROOT = Path(__file__).resolve().parents[2]
POLICY = ROOT / "internal_data" / "input_candidate_model_policy.json"


def _create_source_database(path: Path) -> Path:
    with sqlite3.connect(path) as connection:
        connection.executescript(
            """
            CREATE TABLE accepted_readings (
                text TEXT NOT NULL,
                source TEXT NOT NULL,
                source_category TEXT NOT NULL
            );
            CREATE TABLE canonical_readings (
                id INTEGER PRIMARY KEY,
                text TEXT NOT NULL,
                marked_pinyin TEXT NOT NULL,
                numeric_pinyin TEXT NOT NULL,
                reading_rank INTEGER NOT NULL,
                is_primary INTEGER NOT NULL,
                bcc_frequency INTEGER NOT NULL,
                pinyin_sources TEXT NOT NULL,
                reading_source_categories TEXT NOT NULL
            );
            CREATE TABLE bcc_frequency (
                text TEXT PRIMARY KEY,
                frequency INTEGER NOT NULL
            );
            CREATE TABLE rejections (
                text TEXT NOT NULL,
                reason TEXT NOT NULL
            );
            """
        )
        connection.executemany(
            "INSERT INTO accepted_readings VALUES (?, ?, ?)",
            (
                ("张大千", "wanxiang", "mingren"),
                ("为了", "wanxiang", "jichu"),
                ("人民", "pypinyin", "phrase"),
            ),
        )
        connection.executemany(
            "INSERT INTO canonical_readings VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                (1, "张大千", "zhāng dà qiān", "zhang1 da4 qian1", 1, 1, 900, "wanxiang", "wanxiang:mingren"),
                (2, "为了", "wèi le", "wei4 le5", 1, 1, 800, "wanxiang", "wanxiang:jichu"),
                (3, "人民", "rén mín", "ren2 min2", 1, 1, 700, "pypinyin", "pypinyin:phrase"),
            ),
        )
        connection.executemany(
            "INSERT INTO bcc_frequency VALUES (?, ?)",
            (("张大千", 900), ("为了", 800), ("人民", 700), ("的时候我", 600)),
        )
    return path


def _approved_component(text: str, reading_id: int) -> CandidateAssessment:
    return CandidateAssessment(
        text=text,
        candidate_class=CandidateClass.LEXICAL_CANDIDATE,
        integration_policy=IntegrationPolicy.DYNAMIC_COMPONENT,
        status=DecisionStatus.APPROVED,
        rationale="测试中明确批准为动态组件。",
        assessor="test:reviewer",
        allowed_reading_ids=(reading_id,),
    )


def test_build_catalogs_the_complete_source_universe(tmp_path: Path) -> None:
    source_database = _create_source_database(tmp_path / "source.sqlite3")
    output_database = tmp_path / "input_model.sqlite3"

    result = build_input_model(
        source_database=source_database,
        output_database=output_database,
        policy_path=POLICY,
    )

    assert result.universe_count == 4
    assert result.review_queue_count == 4
    assert result.decision_overlays == 0
    assert result.overlay_status_counts == {}
    with InputModelStore(output_database) as store:
        assert store.universe_count() == 4
        assert store.get("张大千") is None
        person = store.effective("张大千")
        assert person is not None
        assert person.candidate_class is CandidateClass.PERSON_NAME
        assert person.integration_policy is IntegrationPolicy.STATIC_KEEP
        assert person.status is DecisionStatus.PROPOSED

        unresolved = store.effective("的时候我")
        assert unresolved is not None
        assert unresolved.candidate_class is CandidateClass.UNKNOWN
        assert unresolved.integration_policy is IntegrationPolicy.NEEDS_REVIEW
        assert not unresolved.evidence["has_gated_reading"]
        context = ContextEvidence(
            text="的时候我",
            left_context="就在这个",
            matched_text="的时候我",
            right_context="发现了问题",
            source="bcc_kwic",
            source_reference="fixture:1",
        )
        assert store.add_context(context)
        assert not store.add_context(context)
        assert store.contexts("的时候我") == (context,)
        assert store.connection.execute("SELECT COUNT(*) FROM v_review_queue").fetchone()[0] == 4
        with pytest.raises(ValueError, match="outside the candidate universe"):
            store.put(_approved_component("来源外材料", 999))

    with SourceLexicon(source_database) as source:
        assert source.readings("的时候我") == ()
        assert source.readings("张大千")[0].marked == "zhāng dà qiān"


def test_dynamic_composition_uses_only_approved_attested_readings(tmp_path: Path) -> None:
    source_database = _create_source_database(tmp_path / "source.sqlite3")
    output_database = tmp_path / "input_model.sqlite3"
    build_input_model(
        source_database=source_database,
        output_database=output_database,
        policy_path=POLICY,
    )

    with InputModelStore(output_database) as store, SourceLexicon(source_database) as source:
        store.put(_approved_component("为了", 2))
        store.put(_approved_component("人民", 3))
        candidates = DynamicComposer(
            source,
            store,
            policy=CompositionPolicy.from_path(POLICY),
        ).compose("为了人民")
        assert len(candidates) == 1
        assert candidates[0].parts == ("为了", "人民")
        assert candidates[0].marked_pinyin == "wèi le rén mín"
        assert candidates[0].numeric_pinyin == "wei4 le5 ren2 min2"
        assert candidates[0].reading_ids == (2, 3)
        assert DynamicComposer(source, store).compose("的时候我") == ()


def test_rebuild_does_not_overwrite_reviewed_decision(tmp_path: Path) -> None:
    source_database = _create_source_database(tmp_path / "source.sqlite3")
    output_database = tmp_path / "input_model.sqlite3"
    build_input_model(
        source_database=source_database,
        output_database=output_database,
        policy_path=POLICY,
    )
    with InputModelStore(output_database) as store:
        proposal = store.effective("张大千")
        assert proposal is not None
        store.put(
            CandidateAssessment(
                text=proposal.text,
                candidate_class=proposal.candidate_class,
                integration_policy=proposal.integration_policy,
                status=DecisionStatus.APPROVED,
                rationale="人工确认该专名作为静态材料保留。",
                assessor="human:test",
                allowed_reading_ids=(1,),
            )
        )

    result = build_input_model(
        source_database=source_database,
        output_database=output_database,
        policy_path=POLICY,
    )
    assert result.universe_count == 4
    assert result.review_queue_count == 3
    assert result.decision_overlays == 1
    with InputModelStore(output_database) as store:
        assert store.effective("张大千").status is DecisionStatus.APPROVED  # type: ignore[union-attr]

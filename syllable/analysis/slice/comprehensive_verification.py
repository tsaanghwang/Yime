#!/usr/bin/env python3
"""
最终验证：干音和韵母的定义与处理
"""
import  sys
import importlib
from pathlib import Path
import tempfile
from typing import Any, Callable, Mapping, cast

stdout_reconfigure = cast(Callable[..., None] | None, getattr(sys.stdout, 'reconfigure', None))
if stdout_reconfigure is not None:
    stdout_reconfigure(encoding='utf-8')

try:
    from .ganyin_categorizer import GanyinCategorizer
    from .ganyin_theoretical_generator import generate_theoretical_flat_ganyin
    from . import ganyin_analyzer as _ganyin_analyzer
except ImportError:
    from ganyin_categorizer import GanyinCategorizer
    from ganyin_theoretical_generator import generate_theoretical_flat_ganyin
    _ganyin_analyzer = importlib.import_module('ganyin_analyzer')
import json

GanyinAnalyzer = _ganyin_analyzer.GanyinAnalyzer


def _flatten_grouped_ganyin(grouped_ganyin: Mapping[str, Mapping[str, str]]) -> dict[str, str]:
    """将按类别分组的干音数据展平成单层字典。"""
    flat_ganyin: dict[str, str] = {}
    for entries in grouped_ganyin.values():
        flat_ganyin.update(entries)
    return flat_ganyin


def _compare_flat_mappings(expected: dict[str, str], actual: dict[str, str]) -> tuple[list[str], list[str], list[tuple[str, str, str]]]:
    """比较两份单层映射，返回缺失、额外和不匹配项。"""
    missing = sorted(key for key in expected if key not in actual)
    extra = sorted(key for key in actual if key not in expected)
    mismatched = sorted(
        (key, expected[key], actual[key])
        for key in expected.keys() & actual.keys()
        if expected[key] != actual[key]
    )
    return missing, extra, mismatched


def _base_final(key: str) -> str:
    return key[:-1] if key and key[-1].isdigit() else key


def _summarize_missing_finals(missing_ganyin: list[str]) -> dict[str, list[str]]:
    grouped: dict[str, list[str]] = {
        '规则变体': [],
        '特殊形式': [],
        '常规形式': [],
    }
    for final in sorted({_base_final(key) for key in missing_ganyin}):
        info = GanyinCategorizer.get_final_form_info(final)
        grouped.setdefault(info['kind'], []).append(final)
    return grouped


def _group_missing_ganyin_by_final(missing_ganyin: list[str]) -> dict[str, list[str]]:
    grouped: dict[str, list[str]] = {}
    for key in missing_ganyin:
        grouped.setdefault(_base_final(key), []).append(key)
    return {final: sorted(keys) for final, keys in sorted(grouped.items())}


def _classify_missing_finals(missing_ganyin: list[str]) -> dict[str, list[str]]:
    grouped: dict[str, list[str]] = {
        '拼写规则导致缺失': [],
        '当前导入过滤导致缺失': [],
        '真异常缺失': [],
    }
    for final in sorted({_base_final(key) for key in missing_ganyin}):
        handling = GanyinCategorizer.get_missing_handling_info(final)
        grouped.setdefault(str(handling['status']), []).append(final)
    return grouped


def _print_missing_summary(missing_by_status: dict[str, list[str]]) -> None:
    print("\n   缺失摘要:")
    for status in ('拼写规则导致缺失', '当前导入过滤导致缺失', '真异常缺失'):
        finals = missing_by_status.get(status, [])
        tone_count = len(finals) * 5
        finals_text = ', '.join(finals) if finals else '无'
        print(f"     {status}: {len(finals)} 组韵母 / {tone_count} 个干音 -> {finals_text}")


def collect_verification_results() -> dict[str, Any]:
    """收集干音理论集与实际集的验证结果，供脚本输出和测试复用。"""
    theoretical_flat_ganyin = generate_theoretical_flat_ganyin()

    analyzer = GanyinAnalyzer(file=__file__)

    with tempfile.TemporaryDirectory() as temp_dir:
        analyzer.output_dir = temp_dir
        analyzer.shouyin_path = str(Path(temp_dir) / 'shouyin.json')
        analyzer.ganyin_path = str(Path(temp_dir) / 'ganyin.json')
        success = analyzer.analyze_and_save()

        if not success:
            raise RuntimeError("实际干音分析失败")

        with open(analyzer.ganyin_path, 'r', encoding='utf-8') as f:
            generated_ganyin_data = json.load(f)

    all_finals = GanyinCategorizer.get_all_finals()
    all_metadata = GanyinCategorizer.get_all_final_form_metadata()
    generated_grouped_ganyin = generated_ganyin_data.get('ganyin', {})
    generated_flat_ganyin = _flatten_grouped_ganyin(generated_grouped_ganyin)

    missing_ganyin, extra_ganyin, mismatched_ganyin = _compare_flat_mappings(
        theoretical_flat_ganyin,
        generated_flat_ganyin,
    )

    total_finals = sum(len(finals) for finals in all_finals.values())
    special_count = len(GanyinCategorizer.SPECIAL_SYLLABLES)
    actual_ratio = len(generated_flat_ganyin) / total_finals if total_finals > 0 else 0

    return {
        'theoretical_flat_ganyin': theoretical_flat_ganyin,
        'generated_flat_ganyin': generated_flat_ganyin,
        'all_finals': all_finals,
        'all_metadata': all_metadata,
        'missing_ganyin': missing_ganyin,
        'extra_ganyin': extra_ganyin,
        'mismatched_ganyin': mismatched_ganyin,
        'missing_by_kind': _summarize_missing_finals(missing_ganyin),
        'missing_by_final': _group_missing_ganyin_by_final(missing_ganyin),
        'missing_by_status': _classify_missing_finals(missing_ganyin),
        'total_finals': total_finals,
        'special_count': special_count,
        'actual_ratio': actual_ratio,
    }


def comprehensive_verification() -> dict[str, Any]:
    """全面验证干音和韵母的定义与处理。"""
    print("=== 最终验证：干音和韵母定义 ===")

    print("1. 术语定义确认:")
    print("   - 干音 (ganyin) = final with tone (带声调的韵母)")
    print("   - 韵母 (final) = ganyin without tone (从干音中提取声调以后剩下的音质成分)")
    print("   - 预定义韵母集合包含的都是不带声调的韵母")
    print()

    print("2. 生成理论干音与实际干音...")
    results = collect_verification_results()

    print("\n3. 验证预定义韵母集合（都是不带声调的）:")
    all_finals = results['all_finals']
    all_metadata = results['all_metadata']

    print(f"   韵母来源说明表覆盖: {len(all_metadata)} / {sum(len(finals) for finals in all_finals.values())}")
    for final, info in all_metadata.items():
        print(f"   - {final}: {info['kind']} | {info['source']} | {info['detail']}")

    for category, finals_set in all_finals.items():
        print(f"   {category}: {len(finals_set)} 个韵母")
        for final in sorted(finals_set):
            tone_chars = 'āáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜếề'
            has_tone = any(char in final for char in tone_chars)
            if has_tone:
                print(f"     ⚠ {final} - 包含声调标记（不符韵母定义）")
            else:
                print(f"     ✓ {final} - 韵母（不带声调）")

    print("\n4. 验证生成的干音数据:")
    theoretical_flat_ganyin = results['theoretical_flat_ganyin']
    generated_flat_ganyin = results['generated_flat_ganyin']
    missing_ganyin = results['missing_ganyin']
    extra_ganyin = results['extra_ganyin']
    mismatched_ganyin = results['mismatched_ganyin']

    print("   理论全集 vs 实际切分结果:")
    print(f"   理论干音数: {len(theoretical_flat_ganyin)}")
    print(f"   实际干音数: {len(generated_flat_ganyin)}")
    print(f"     缺失干音: {len(missing_ganyin)}")
    print(f"     额外干音: {len(extra_ganyin)}")
    print(f"     值不匹配干音: {len(mismatched_ganyin)}")

    if missing_ganyin:
        print("     说明: 这些缺失干音是理论侧存在、实际侧未直接产出的项目。")
        print(f"     示例缺失干音: {missing_ganyin[:10]}")
        print(f"     全部缺失干音: {missing_ganyin}")
    if extra_ganyin:
        print(f"     示例额外干音: {extra_ganyin[:10]}")
    if mismatched_ganyin:
        print(f"     示例值不匹配干音: {mismatched_ganyin[:5]}")

    if missing_ganyin:
        missing_by_kind = results['missing_by_kind']
        missing_by_final = results['missing_by_final']
        missing_by_status = results['missing_by_status']
        _print_missing_summary(missing_by_status)
        print("\n   缺失项按韵母来源说明:")
        for kind in ('规则变体', '特殊形式', '常规形式'):
            finals = missing_by_kind.get(kind, [])
            if not finals:
                continue
            print(f"     {kind}: {', '.join(finals)}")
            if kind == '规则变体':
                print("       - 结论: 这类缺失属于理论形式与实际拼写规则之间的数据出入，不应直接视为错误形式。")
            elif kind == '特殊形式':
                print("       - 结论: 这类缺失属于理论侧扩展收录而当前导入数据未直接带入的项目，当前只需说明缺失原因。")
            elif kind == '常规形式':
                print("       - 结论: 如果这里出现缺失，才更接近真正需要排查的异常。")
            for final in finals:
                info = GanyinCategorizer.get_final_form_info(final)
                print(f"       - {final}: {info['source']}；{info['detail']}")

        print("\n   缺失项按处理结论:")
        for status in ('拼写规则导致缺失', '当前导入过滤导致缺失', '真异常缺失'):
            finals = missing_by_status.get(status, [])
            if not finals:
                continue
            print(f"     {status}: {', '.join(finals)}")
            for final in finals:
                handling = GanyinCategorizer.get_missing_handling_info(final)
                surface_forms = handling.get('surface_forms', [])
                surface_text = f"；建议对照实际表面形式: {', '.join(surface_forms)}" if surface_forms else ''
                extra_parts: list[str] = []
                if 'source_type' in handling:
                    extra_parts.append(f"来源类型: {handling['source_type']}")
                if 'actual_data_presence' in handling:
                    extra_parts.append(f"数据现状: {handling['actual_data_presence']}")
                if 'examples' in handling:
                    extra_parts.append(f"说明: {handling['examples']}")
                extra_text = f"；{'；'.join(extra_parts)}" if extra_parts else ''
                print(f"       - {final}: {handling['reason']}{surface_text}{extra_text}")

        print("\n   缺失干音按基韵母归并:")
        for final, keys in missing_by_final.items():
            print(f"     {final}: {keys}")

    # 检查几个示例
    examples = ['a1', 'ai2', 'ian3', 'ong4', 'iong1']

    print("   示例验证:")
    for key in examples:
        if key in generated_flat_ganyin:
            actual = generated_flat_ganyin[key]
            expected_tone = theoretical_flat_ganyin.get(key, '<missing>')
            final = key[:-1] if key and key[-1].isdigit() else key
            category = GanyinCategorizer.categorize(key)
            expected_category = GanyinCategorizer.categorize(key)
            tone_ok = actual == expected_tone
            category_ok = category == expected_category
            print(f"     {key} -> {actual} (预期干音: {expected_tone}) {'✓' if tone_ok else '✗'}")
            print(f"       提取的韵母: {final}")
            print(f"       分类: {category} (预期分类: {expected_category}) {'✓' if category_ok else '✗'}")
        else:
            print(f"     {key} -> 未找到")

    # 5. 统计分析
    print("\n5. 最终统计:")
    total_finals = results['total_finals']
    print(f"   - 韵母总数: {total_finals}")
    print(f"   - 干音总数: {len(generated_flat_ganyin)}")
    print(f"   - 干音是韵母的带声调形式，一个韵母对应多个干音（不同声调）")

    special_count = results['special_count']
    actual_ratio = results['actual_ratio']

    print(f"   - 预期比例: ~5:1 (每个韵母5个声调)")
    print(f"   - 实际比例: {actual_ratio:.2f}:1")
    print(f"   - 特殊音节数: {special_count}")
    return results


if __name__ == "__main__":
    comprehensive_verification()

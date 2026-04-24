"""单音节编码排查脚本。"""

from syllable.analysis.slice.ganyin_encoder import GanyinEncoder
from syllable.analysis.slice.shouyin_encoder import ShouyinEncoder
from syllable.analysis.slice.syllable_encoding_pipeline import SyllableEncodingPipeline
from yinjie_encoder import YinjieEncoder


def format_codepoints(value: str) -> str:
    if not value:
        return "(empty)"
    return " ".join(f"U+{ord(char):04X}" for char in value)


def inspect_syllable(syllable: str) -> None:
    normalized = SyllableEncodingPipeline.normalize_syllable(syllable)
    shouyin, ganyin = SyllableEncodingPipeline.split_normalized_syllable(normalized)

    shouyin_encoder = ShouyinEncoder()
    ganyin_encoder = GanyinEncoder()
    yinjie_encoder = YinjieEncoder()

    shouyin_code = shouyin_encoder.encode_shouyin(shouyin)
    ganyin_code = ganyin_encoder.encode_ganyin(ganyin)
    final_code = yinjie_encoder.encode_single_yinjie(syllable)

    print(f"输入拼音: {syllable}")
    print(f"规范化结果: {normalized}")
    print(f"切分结果: shouyin={shouyin!r}, ganyin={ganyin!r}")
    print(f"首音码: {shouyin_code} [{format_codepoints(shouyin_code)}]")
    print(f"干音码: {ganyin_code} [{format_codepoints(ganyin_code)}]")
    print(f"最终码: {final_code} [{format_codepoints(final_code)}]")


def main() -> None:
    print("拼音编码排查模式 (输入 q 退出)")

    while True:
        syllable = input("请输入要排查的拼音：").strip()
        if syllable.lower() == "q":
            break

        if not syllable:
            print("拼音不能为空")
            print()
            continue

        try:
            inspect_syllable(syllable)
        except Exception as error:
            print(f"排查失败: {error}")

        print()


if __name__ == "__main__":
    main()

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, cast

try:
    from .paths import KEY_TO_CODE_PATH, PACKAGE_ROOT, REPO_ROOT, YINJIE_CODE_PATH
    from .yinjie import Yinjie
except ImportError:
    from paths import KEY_TO_CODE_PATH, PACKAGE_ROOT, REPO_ROOT, YINJIE_CODE_PATH
    from yinjie import Yinjie


DecodedMap = dict[str, Yinjie]
YinyuanSets = dict[str, set[str]]
PhonemeSets = YinyuanSets
ROOT = PACKAGE_ROOT
DEFAULT_YINYUAN_REPORT = REPO_ROOT / 'yime' / 'reports' / 'yinyuan_dict.json'
DEFAULT_PHONEME_REPORT = REPO_ROOT / 'yime' / 'reports' / 'phoneme_dict.json'


@dataclass(frozen=True)
class YinjieDecoderRunResult:
    """统一运行入口的输出结果。"""

    decoded_count: int
    phoneme_dict_path: Path
    key_to_code_path: Path

    @property
    def yinyuan_dict_path(self) -> Path:
        """推荐名：音元分类导出路径。"""
        return self.phoneme_dict_path

class YinjieDecoder:
    # === 初始化相关 ===
    def __init__(self, code_file: str | Path = YINJIE_CODE_PATH):
        """初始化解码器，加载编码文件"""
        self.code_file = Path(code_file)
        self.code_map: dict[str, str] = self._load_code_map()

    def _load_code_map(self) -> dict[str, str]:
        """从JSON文件加载编码映射"""
        with self.code_file.open('r', encoding='utf-8') as f:
            return json.load(f)

    def _save_json(self, output_file: str | Path, data: Any) -> Path:
        """统一的 JSON 写入入口。"""
        output_path = Path(output_file)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with output_path.open('w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        return output_path

    def _get_shouyin_source_path(self) -> Path:
        return REPO_ROOT / 'syllable' / 'yinyuan' / 'zaoyin_yinyuan_enhanced.json'

    def _get_yueyin_source_path(self) -> Path:
        return REPO_ROOT / 'syllable' / 'yinyuan' / 'yueyin_yinyuan_enhanced.json'

    def _load_yinyuan_id_mapping_from_source(self, source_path: Path, expected_prefix: str) -> dict[str, str]:
        with source_path.open('r', encoding='utf-8') as f:
            source_data = json.load(f)

        entries = source_data.get('entries')
        if not isinstance(entries, dict) or not entries:
            raise ValueError(f"真源文件缺少 entries: {source_path}")
        typed_entries = cast(dict[str, Any], entries)

        keyed_entries: list[tuple[int, str, str]] = []
        for entry_name, entry in typed_entries.items():
            if not isinstance(entry, dict):
                raise ValueError(f"真源条目格式不正确: {source_path} -> {entry_name}")
            entry_dict = cast(dict[str, Any], entry)

            yinyuan_id = entry_dict.get('yinyuan_id')
            runtime_char = entry_dict.get('runtime_char')
            if not isinstance(yinyuan_id, str) or not yinyuan_id:
                raise ValueError(f"真源条目缺少 yinyuan_id: {source_path} -> {entry_name}")
            if not isinstance(runtime_char, str) or not runtime_char:
                raise ValueError(f"真源条目缺少 runtime_char: {source_path} -> {entry_name}")
            if not yinyuan_id.startswith(expected_prefix):
                raise ValueError(
                    f"真源条目 Yinyuan ID 前缀不正确: {source_path} -> {entry_name} uses {yinyuan_id}, expected {expected_prefix}xx"
                )

            try:
                id_index = int(yinyuan_id[1:])
            except ValueError as exc:
                raise ValueError(f"真源条目 Yinyuan ID 不正确: {source_path} -> {entry_name} uses {yinyuan_id}") from exc

            keyed_entries.append((id_index, yinyuan_id, runtime_char))

        keyed_entries.sort(key=lambda item: item[0])

        yinyuan_id_to_char: dict[str, str] = {}
        for _, yinyuan_id, runtime_char in keyed_entries:
            if yinyuan_id in yinyuan_id_to_char:
                raise ValueError(f"真源条目出现重复 Yinyuan ID: {source_path} -> {yinyuan_id}")
            yinyuan_id_to_char[yinyuan_id] = runtime_char

        return yinyuan_id_to_char

    # === 显示辅助方法 ===
    def _display_char(self, char: str) -> str:
        """辅助函数：直接返回字符本身而不是Unicode转义序列"""
        return char if char else ''

    def _display_yinyuan_chars(self, yinyuan_chars: list[str]) -> str:
        """改进的音元列表显示方法"""
        if not yinyuan_chars:
            return "[]"
        return "[" + ", ".join(f"'{self._display_char(c)}'" for c in yinyuan_chars) + "]"

    def _display_phonemes(self, phonemes: list[str]) -> str:
        """兼容旧名：同 ``_display_yinyuan_chars``。"""
        return self._display_yinyuan_chars(phonemes)

    # === 核心解码功能 ===
    def decode(self, pinyin: str) -> Yinjie:
        """解码单个拼音为Yinjie实例"""
        code = self.resolve_code(pinyin)
        if not code:
            raise ValueError(f"未找到拼音 '{pinyin}' 的编码")

        if len(code) != 4:
            raise ValueError(f"编码 '{code}' 长度不正确，应为4个字符")

        return Yinjie.from_code(code)

    def resolve_code(self, key: str) -> str | None:
        """按带调拼音键或四码值反查 canonical 编码串。"""
        if key in self.code_map:
            return self.code_map[key]
        for value in self.code_map.values():
            if value == key:
                return value
        return None

    @staticmethod
    def split_encoded_string(encoded: str) -> Yinjie:
        """切分四字符音元编码串为 ``Yinjie``。"""
        if not encoded:
            raise ValueError("encoded syllable required")
        if len(encoded) != 4:
            raise ValueError("encoded syllable length must be 4")
        return Yinjie.from_code(encoded)

    def decode_all(self) -> DecodedMap:
        """解码所有拼音为Yinjie实例字典"""
        return {pinyin: self.decode(pinyin) for pinyin in self.code_map}

    def _collect_yinyuan_sets(self, decoded_map: DecodedMap) -> YinyuanSets:
        """从已解码结果中收集噪音和乐音集合。"""
        yinyuan_sets: YinyuanSets = {
            "noise": set(),
            "musical": set(),
        }

        for yinjie in decoded_map.values():
            noise, musical = yinjie.classify_yinyuan_chars()
            yinyuan_sets["noise"].update(noise)
            yinyuan_sets["musical"].update(musical)

        return yinyuan_sets

    def _collect_phoneme_sets(self, decoded_map: DecodedMap) -> PhonemeSets:
        """兼容旧名：同 ``_collect_yinyuan_sets``。"""
        return self._collect_yinyuan_sets(decoded_map)

    # === 音元分类和映射生成 ===
    def generate_yinyuan_mapping(self, decoded_map: DecodedMap | None = None) -> dict[str, Any]:
        """生成音元分类映射字典"""
        decoded_map = decoded_map or self.decode_all()
        mapping = self._collect_yinyuan_sets(decoded_map)

        return {
            "forward": {
                "noise": sorted(mapping["noise"]),
                "musical": sorted(mapping["musical"])
            },
            "reverse": {
                yinyuan_char: "noise" for yinyuan_char in mapping["noise"]
            }
        }

    def generate_phoneme_mapping(self, decoded_map: DecodedMap | None = None) -> dict[str, Any]:
        """兼容旧名：同 ``generate_yinyuan_mapping``。"""
        return self.generate_yinyuan_mapping(decoded_map=decoded_map)

    def build_yinyuan_dict(self, decoded_map: DecodedMap | None = None) -> dict[str, list[str]]:
        """从已解码结果构造音元分类字典。"""
        decoded_map = decoded_map or self.decode_all()
        yinyuan_sets = self._collect_yinyuan_sets(decoded_map)
        return {
            "noise_yinyuan": sorted(yinyuan_sets["noise"]),
            "musical_yinyuan": sorted(yinyuan_sets["musical"]),
        }

    def build_phoneme_dict(self, decoded_map: DecodedMap | None = None) -> dict[str, list[str]]:
        """兼容旧名：返回历史 JSON 键名。"""
        decoded_map = decoded_map or self.decode_all()
        yinyuan_sets = self._collect_yinyuan_sets(decoded_map)
        return {
            "noise_phonemes": sorted(yinyuan_sets["noise"]),
            "musical_phonemes": sorted(yinyuan_sets["musical"]),
        }

    # === 文件操作和保存 ===
    def save_yinyuan_dict(self, output_file: str | Path = DEFAULT_YINYUAN_REPORT, decoded_map: DecodedMap | None = None) -> Path:
        """将分类后的音元保存到JSON文件"""
        yinyuan_dict = self.build_yinyuan_dict(decoded_map=decoded_map)
        return self._save_json(output_file, yinyuan_dict)

    def save_phoneme_dict(self, output_file: str | Path = DEFAULT_PHONEME_REPORT, decoded_map: DecodedMap | None = None) -> Path:
        """兼容旧名：保存历史 JSON 键名。"""
        phoneme_dict = self.build_phoneme_dict(decoded_map=decoded_map)
        return self._save_json(output_file, phoneme_dict)

    def _build_category_keys(self, yinyuan_chars: list[str], prefix: str) -> dict[str, str]:
        """按类别前缀生成等长编码键。"""
        return {
            f"{prefix}{index:02d}": yinyuan_char
            for index, yinyuan_char in enumerate(yinyuan_chars, start=1)
        }

    def map_key_to_code(self, output_file: str | Path = KEY_TO_CODE_PATH, decoded_map: DecodedMap | None = None) -> dict[str, str]:
        """从当前真源条目生成类别前缀键到 PUA 字符的映射字典并保存到文件。"""
        noise_keys = self._load_yinyuan_id_mapping_from_source(self._get_shouyin_source_path(), 'N')
        musical_keys = self._load_yinyuan_id_mapping_from_source(self._get_yueyin_source_path(), 'M')

        key_to_code = {
            **noise_keys,
            **musical_keys,
        }

        output_path = self._save_json(output_file, key_to_code)

        print(f"已生成并保存键位映射到 {output_path}")
        return key_to_code

    def show_examples(self, examples: list[str], decoded_map: DecodedMap | None = None) -> None:
        """输出示例拼音的解码结果。"""
        decoded_map = decoded_map or self.decode_all()
        for pinyin in examples:
            try:
                yinjie = decoded_map[pinyin]
                print(f"\n解码 '{pinyin}':")
                print(f"音节线性结构: {yinjie}")
                noise, musical = yinjie.classify_yinyuan_chars()
                print(f"噪音音元: {self._display_yinyuan_chars(noise)}")
                print(f"乐音音元: {self._display_yinyuan_chars(musical)}")
            except KeyError:
                print(f"解码 '{pinyin}' 时出错: 未找到拼音 '{pinyin}' 的编码")
            except ValueError as e:
                print(f"解码 '{pinyin}' 时出错: {e}")

    def run(
        self,
        yinyuan_output: str | Path = DEFAULT_YINYUAN_REPORT,
        key_output: str | Path = KEY_TO_CODE_PATH,
        examples: list[str] | None = None,
        phoneme_output: str | Path | None = None,
    ) -> YinjieDecoderRunResult:
        """统一调用入口：一次全量解码后完成导出与示例输出。"""
        decoded_map = self.decode_all()
        report_output = phoneme_output if phoneme_output is not None else yinyuan_output
        if phoneme_output is not None:
            yinyuan_dict_path = self.save_phoneme_dict(report_output, decoded_map=decoded_map)
        else:
            yinyuan_dict_path = self.save_yinyuan_dict(report_output, decoded_map=decoded_map)
        if examples:
            self.show_examples(examples, decoded_map=decoded_map)

        print(f"\n解码了 {len(decoded_map)} 个音节")
        self.map_key_to_code(key_output, decoded_map=decoded_map)
        return YinjieDecoderRunResult(
            decoded_count=len(decoded_map),
            phoneme_dict_path=yinyuan_dict_path,
            key_to_code_path=Path(key_output),
        )

    # === 主程序示例 ===
    @staticmethod
    def run_example() -> YinjieDecoderRunResult:
        """运行解码器示例"""
        decoder = YinjieDecoder()
        return decoder.run(examples=["ma1", "ni3", "hao3", "shang4", "xia4"])


def main() -> None:
    """模块统一 CLI 入口。"""
    YinjieDecoder.run_example()

if __name__ == "__main__":
    main()

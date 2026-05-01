"""音节编码入口，统一负责输入定位、切分编码与结果输出。"""

import json
import logging
import sys
from collections.abc import Callable
from dataclasses import dataclass
from typing import NoReturn
from pathlib import Path
from typing import Any

try:
    from .yinjie_api_manifest import YINJIE_IMPLEMENTATION_EXPORTS
    from .syllable_encoding_pipeline import SyllableEncodingPipeline
    from .shouyin_encoder import ShouyinEncoder
    from .ganyin_encoder import GanyinEncoder
except ImportError:
    from yinjie_api_manifest import YINJIE_IMPLEMENTATION_EXPORTS
    from syllable_encoding_pipeline import SyllableEncodingPipeline
    from shouyin_encoder import ShouyinEncoder
    from ganyin_encoder import GanyinEncoder
# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class YinjieEncodingError(ValueError):
    """音节编码流程中的统一异常类型。"""

    def __init__(
        self,
        message: str,
        *,
        stage: str,
        syllable: str | None = None,
        detail: str | None = None,
        failures: list[tuple[str, str]] | None = None,
    ):
        super().__init__(message)
        self.stage = stage
        self.syllable = syllable
        self.detail = detail or message
        self.failures = failures or []


class YinjieErrorPolicy:
    """集中定义音节编码流程的异常构造契约。"""

    def invalid_path(self, path: Path) -> YinjieEncodingError:
        return YinjieEncodingError(
            f"路径不存在: {path}",
            stage="path",
            detail=str(path),
        )

    def missing_project_root(self) -> YinjieEncodingError:
        return YinjieEncodingError(
            "无法找到项目根目录(包含pinyin目录)",
            stage="setup",
        )

    def invalid_input(self, syllable: object) -> YinjieEncodingError:
        return YinjieEncodingError(
            "音节参数必须是非空字符串",
            stage="input",
            syllable=repr(syllable),
        )

    def syllable_failure(self, stage: str, syllable: str, detail: str) -> YinjieEncodingError:
        return YinjieEncodingError(
            f"音节 '{syllable}' 在 {stage} 阶段失败: {detail}",
            stage=stage,
            syllable=syllable,
            detail=detail,
        )

    def batch_failure(self, failures: list[tuple[str, str]]) -> YinjieEncodingError:
        failure_summary = "; ".join(
            f"{syllable}: {detail}"
            for syllable, detail in failures
        )
        return YinjieEncodingError(
            f"共有 {len(failures)} 个音节编码失败，未生成 syllable_codec/yinjie_code.json: {failure_summary}",
            stage="batch",
            detail=failure_summary,
            failures=failures,
        )

    def invalid_assemble_pair(
        self,
        shouyin_syllable: str,
        ganyin_syllable: str,
    ) -> YinjieEncodingError:
        return YinjieEncodingError(
            "首音编码与干音编码对应的音节不一致",
            stage="assemble",
            detail=f"shouyin={shouyin_syllable}, ganyin={ganyin_syllable}",
        )

    def load_input_failure(self, detail: str) -> YinjieEncodingError:
        return YinjieEncodingError(
            f"加载音节输入数据失败: {detail}",
            stage="load_input",
            detail=detail,
        )

    def save_output_failure(self, detail: str) -> YinjieEncodingError:
        return YinjieEncodingError(
            f"保存音节编码文件失败: {detail}",
            stage="save_output",
            detail=detail,
        )


yinjie_error_policy = YinjieErrorPolicy()


class YinjieReportingPolicy:
    """集中定义音节编码流程的日志契约。"""

    def ignored_output_subdir(self, stage_logger: logging.Logger, output_subdir: str) -> None:
        stage_logger.warning(
            "已忽略 output_subdir='%s'；当前使用统一输出路径。",
            output_subdir,
        )

    def syllable_encoding_failure(
        self,
        stage_logger: logging.Logger,
        syllable: str,
        detail: str,
    ) -> None:
        stage_logger.warning("音节 '%s' 编码失败: %s", syllable, detail)

    def output_generated(self, stage_logger: logging.Logger, output_path: Path) -> None:
        stage_logger.info("成功生成编码文件: %s", output_path)

    def program_failure(self, stage_logger: logging.Logger, error: Exception) -> None:
        stage_logger.error("程序执行失败: %s", error)


yinjie_reporting_policy = YinjieReportingPolicy()


class YinjieCliPolicy:
    """集中定义终端输出与退出行为契约。"""

    def __init__(
        self,
        output_writer: Callable[[str], None] | None = None,
        exit_handler: Callable[[int], None] | None = None,
        reporting_policy: YinjieReportingPolicy | None = None,
        stage_logger: logging.Logger | None = None,
    ):
        self.output_writer = output_writer or print
        self.exit_handler = exit_handler or sys.exit
        self.reporting_policy = reporting_policy or yinjie_reporting_policy
        self.stage_logger = stage_logger or logger

    def main_success(self, output_path: Path) -> None:
        self.output_writer(f"编码文件已生成: {output_path}")

    def main_failure(self, error: Exception) -> NoReturn:
        self.reporting_policy.program_failure(self.stage_logger, error)
        self.exit_handler(1)
        raise SystemExit(1)

    def interactive_banner(self) -> None:
        self.output_writer("拼音编码交互工具 (输入q退出)")

    def interactive_empty_input(self) -> None:
        self.output_writer("输入不能为空")

    def interactive_result(self, code: str) -> None:
        self.output_writer(f"编码结果: {code}\n")

    def interactive_known_error(self, error: YinjieEncodingError) -> None:
        self.output_writer(f"错误: {error}")

    def interactive_unexpected_error(self, error: Exception) -> None:
        self.output_writer(f"发生意外错误: {error}")


yinjie_cli_policy = YinjieCliPolicy()


class YinjieApplicationRunner:
    """负责装配编码器与 CLI policy 的应用入口运行器。"""

    def __init__(
        self,
        encoder_factory: Callable[[], "YinjieEncoder"] | None = None,
        cli_policy: YinjieCliPolicy = yinjie_cli_policy,
    ):
        self.encoder_factory = encoder_factory or YinjieEncoder
        self.cli_policy = cli_policy

    def run_main(self) -> None:
        try:
            encoder = self.encoder_factory()
            output_path = encoder.encode_all_yinjie()
            self.cli_policy.main_success(output_path)
        except YinjieEncodingError as error:
            self.cli_policy.main_failure(error)
        except Exception as error:
            self.cli_policy.main_failure(error)


@dataclass(frozen=True)
class SplitSyllableResult:
    """音节切分阶段的输出。"""

    syllable: str
    shouyin: str
    ganyin: str


@dataclass(frozen=True)
class EncodedComponentResult:
    """单个编码部件阶段的输出。"""

    syllable: str
    value: str


@dataclass(frozen=True)
class BatchInputResult:
    """批量编码输入阶段的输出。"""

    input_path: Path
    output_path: Path
    yinjie_list: list[str]


@dataclass(frozen=True)
class YinjiePathContext:
    """编码所需的项目根目录与输入输出路径。"""

    project_root: Path
    input_path: Path
    output_path: Path


class ProjectRootStage:
    """定位包含拼音数据的项目根目录。"""

    def run(self, base_dir: Path) -> Path:
        current = base_dir.resolve()
        while not (current / "pinyin").exists() and current.parent != current:
            current = current.parent

        if not (current / "pinyin").exists():
            raise yinjie_error_policy.missing_project_root()

        return current


class YinjiePathStage:
    """解析统一的输入输出文件路径。"""

    def __init__(
        self,
        path_validator: Callable[[Path], Path],
        output_filename: str,
        stage_logger: logging.Logger | None = None,
        reporting_policy: YinjieReportingPolicy | None = None,
    ):
        self.path_validator = path_validator
        self.output_filename = output_filename
        self.stage_logger = stage_logger or logger
        self.reporting_policy = reporting_policy or yinjie_reporting_policy

    def resolve_input_path(self, project_root: Path) -> Path:
        return self.path_validator(
            project_root / "pinyin" / "hanzi_pinyin" / "pinyin_normalized.json"
        )

    def resolve_output_path(self, project_root: Path, output_subdir: str = "") -> Path:
        if output_subdir:
            self.reporting_policy.ignored_output_subdir(self.stage_logger, output_subdir)
        return project_root / self.output_filename

    def run(self, project_root: Path, output_subdir: str = "") -> YinjiePathContext:
        return YinjiePathContext(
            project_root=project_root,
            input_path=self.resolve_input_path(project_root),
            output_path=self.resolve_output_path(project_root, output_subdir),
        )


class JsonFileRepository:
    """负责 JSON 文件的读取与写入。"""

    def load(self, path: Path) -> dict[str, Any]:
        with path.open("r", encoding="utf-8") as file:
            return json.load(file)

    def save(self, path: Path, data: dict[str, Any]) -> None:
        with path.open("w", encoding="utf-8") as file:
            json.dump(data, file, ensure_ascii=False, indent=2)


class SyllableSplitStage:
    """执行编码所需的音节规范化与切分。"""

    def run(self, syllable: str) -> SplitSyllableResult:
        try:
            parts = SyllableEncodingPipeline.analyze_syllable(syllable)
            if len(parts) != 2:
                raise yinjie_error_policy.syllable_failure(
                    "split",
                    syllable,
                    "音节切分结果无效，应返回(首音,干音)元组",
                )
            shouyin, ganyin = parts
            return SplitSyllableResult(syllable=syllable, shouyin=shouyin, ganyin=ganyin)
        except YinjieEncodingError:
            raise
        except Exception as error:
            raise yinjie_error_policy.syllable_failure("split", syllable, str(error)) from error


class ShouyinEncodeStage:
    """执行首音编码并校验结果。"""

    def __init__(self, encoder: ShouyinEncoder):
        self.encoder = encoder

    def run(self, split_result: SplitSyllableResult) -> EncodedComponentResult:
        try:
            shouyin_code = self.encoder.encode_shouyin(split_result.shouyin)
        except Exception as error:
            raise yinjie_error_policy.syllable_failure(
                "shouyin_encode",
                split_result.syllable,
                str(error),
            ) from error

        if not shouyin_code:
            raise yinjie_error_policy.syllable_failure(
                "shouyin_encode",
                split_result.syllable,
                f"首音 '{split_result.shouyin}' 编码为空",
            )

        return EncodedComponentResult(syllable=split_result.syllable, value=shouyin_code)


class GanyinEncodeStage:
    """执行干音编码并校验结果。"""

    def __init__(self, encoder: GanyinEncoder):
        self.encoder = encoder

    def run(self, split_result: SplitSyllableResult) -> EncodedComponentResult:
        try:
            ganyin_code = self.encoder.encode_ganyin(split_result.ganyin)
        except Exception as error:
            raise yinjie_error_policy.syllable_failure(
                "ganyin_encode",
                split_result.syllable,
                str(error),
            ) from error

        if not ganyin_code or len(ganyin_code) != 3:
            raise yinjie_error_policy.syllable_failure(
                "ganyin_encode",
                split_result.syllable,
                f"干音 '{split_result.ganyin}' 编码无效: {ganyin_code}",
            )

        return EncodedComponentResult(syllable=split_result.syllable, value=ganyin_code)


class YinjieAssembleStage:
    """组装首音与干音编码。"""

    def run(
        self,
        shouyin_result: EncodedComponentResult,
        ganyin_result: EncodedComponentResult,
    ) -> str:
        if shouyin_result.syllable != ganyin_result.syllable:
            raise yinjie_error_policy.invalid_assemble_pair(
                shouyin_result.syllable,
                ganyin_result.syllable,
            )
        return shouyin_result.value + ganyin_result.value


class YinjieBatchInputStage:
    """加载批量编码所需的音节输入。"""

    def run(
        self,
        input_path: Path,
        output_path: Path,
        loader: Callable[[Path], dict[str, Any]],
    ) -> BatchInputResult:
        try:
            pinyin_data = loader(input_path)
            yinjie_list = list(pinyin_data.keys())
        except YinjieEncodingError:
            raise
        except Exception as error:
            raise yinjie_error_policy.load_input_failure(str(error)) from error

        return BatchInputResult(
            input_path=input_path,
            output_path=output_path,
            yinjie_list=yinjie_list,
        )


class YinjieBatchEncodeStage:
    """批量执行单音节编码并汇总失败项。"""

    def __init__(
        self,
        single_encoder: Callable[[str], str],
        stage_logger: logging.Logger | None = None,
        reporting_policy: YinjieReportingPolicy | None = None,
    ):
        self.single_encoder = single_encoder
        self.stage_logger = stage_logger or logger
        self.reporting_policy = reporting_policy or yinjie_reporting_policy

    def run(self, yinjie_list: list[str]) -> dict[str, str]:
        yinjie_code_dict: dict[str, str] = {}
        failed_yinjie: list[tuple[str, str]] = []

        for yinjie in yinjie_list:
            try:
                code = self.single_encoder(yinjie)
                yinjie_code_dict[yinjie] = code
            except YinjieEncodingError as error:
                failed_yinjie.append((yinjie, error.detail))
                self.reporting_policy.syllable_encoding_failure(
                    self.stage_logger,
                    yinjie,
                    error.detail,
                )
            except Exception as error:
                failed_yinjie.append((yinjie, str(error)))
                self.reporting_policy.syllable_encoding_failure(
                    self.stage_logger,
                    yinjie,
                    str(error),
                )

        if failed_yinjie:
            raise yinjie_error_policy.batch_failure(failed_yinjie)

        return yinjie_code_dict


class YinjieBatchOutputStage:
    """保存批量编码结果。"""

    def __init__(
        self,
        stage_logger: logging.Logger | None = None,
        reporting_policy: YinjieReportingPolicy | None = None,
    ):
        self.stage_logger = stage_logger or logger
        self.reporting_policy = reporting_policy or yinjie_reporting_policy

    def run(
        self,
        output_path: Path,
        data: dict[str, str],
        saver: Callable[[Path, dict[str, Any]], None],
    ) -> Path:
        try:
            saver(output_path, data)
        except Exception as error:
            raise yinjie_error_policy.save_output_failure(str(error)) from error

        self.reporting_policy.output_generated(self.stage_logger, output_path)
        return output_path


class YinjieEncoder:
    """音节编码处理器。"""

    OUTPUT_FILENAME = "syllable_codec/yinjie_code.json"

    def __init__(self):
        """初始化编码器并绑定项目根目录。"""
        self.base_dir = Path(__file__).parent
        self.project_root_stage = ProjectRootStage()
        self.project_root = self.project_root_stage.run(self.base_dir)
        self.json_repository = JsonFileRepository()
        self.shouyin_encoder = ShouyinEncoder()
        self.ganyin_encoder = GanyinEncoder()
        self.reporting_policy = yinjie_reporting_policy
        self.path_stage = YinjiePathStage(
            self._validate_path,
            self.OUTPUT_FILENAME,
            reporting_policy=self.reporting_policy,
        )
        self.split_stage = SyllableSplitStage()
        self.shouyin_stage = ShouyinEncodeStage(self.shouyin_encoder)
        self.ganyin_stage = GanyinEncodeStage(self.ganyin_encoder)
        self.assemble_stage = YinjieAssembleStage()
        self.batch_input_stage = YinjieBatchInputStage()
        self.batch_encode_stage = YinjieBatchEncodeStage(
            self.encode_single_yinjie,
            reporting_policy=self.reporting_policy,
        )
        self.batch_output_stage = YinjieBatchOutputStage(
            reporting_policy=self.reporting_policy,
        )

    def _validate_path(self, path: Path) -> Path:
        """验证路径是否存在。"""
        if not path.exists():
            raise yinjie_error_policy.invalid_path(path)
        return path

    def _find_project_root(self) -> Path:
        """定位包含拼音数据的项目根目录。"""
        return self.project_root_stage.run(self.base_dir)

    def encode_single_yinjie(self, syllable: object) -> str:
        """编码单个音节。"""
        if not syllable or not isinstance(syllable, str):
            raise yinjie_error_policy.invalid_input(syllable)

        split_result = self.split_stage.run(syllable)
        shouyin_result = self.shouyin_stage.run(split_result)
        ganyin_result = self.ganyin_stage.run(split_result)
        return self.assemble_stage.run(shouyin_result, ganyin_result)

    def encode_all_yinjie(self, output_subdir: str = "") -> Path:
        """编码全部音节并写入统一输出文件。"""
        path_context = self.path_stage.run(self.project_root, output_subdir)
        input_result = self.batch_input_stage.run(
            path_context.input_path,
            path_context.output_path,
            self._load_json,
        )
        encoded_data = self.batch_encode_stage.run(input_result.yinjie_list)
        return self.batch_output_stage.run(
            input_result.output_path,
            encoded_data,
            self._save_json,
        )

    def _get_input_path(self) -> Path:
        """获取统一输入文件路径。"""
        return self.path_stage.resolve_input_path(self.project_root)

    def _get_output_path(self, subdir: str) -> Path:
        """获取统一输出文件路径。"""
        return self.path_stage.resolve_output_path(self.project_root, subdir)

    def _load_json(self, path: Path) -> dict[str, Any]:
        """加载 JSON 文件。"""
        return self.json_repository.load(path)

    def _save_json(self, path: Path, data: dict[str, Any]) -> None:
        """保存数据到 JSON 文件。"""
        self.json_repository.save(path, data)

    def generate_encoding_files(self) -> Path:
        """兼容旧接口，生成统一输出文件。"""
        return self.encode_all_yinjie()


def main(cli_policy: YinjieCliPolicy | None = None):
    """CLI 主入口。"""
    try:
        from .yinjie_composition import main as composition_main
    except ImportError:
        from yinjie_composition import main as composition_main

    composition_main(cli_policy=cli_policy)


__all__ = YINJIE_IMPLEMENTATION_EXPORTS


if __name__ == "__main__":
    main()

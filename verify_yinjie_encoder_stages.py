import unittest
import tempfile
from pathlib import Path
from interactive_yinjie import interactive_encoder
from syllable.analysis.slice.yinjie_composition import (
    create_default_application_runner,
    create_default_encoder,
    get_default_cli_policy,
    get_default_error_policy,
    get_default_reporting_policy,
    run_default_interactive_session,
)

from yinjie_encoder import (
    YinjieApplicationRunner,
    BatchInputResult,
    EncodedComponentResult,
    GanyinEncodeStage,
    JsonFileRepository,
    ProjectRootStage,
    ShouyinEncodeStage,
    SplitSyllableResult,
    YinjieCliPolicy,
    YinjieAssembleStage,
    YinjieBatchEncodeStage,
    YinjieBatchInputStage,
    YinjieBatchOutputStage,
    YinjieEncoder,
    YinjieEncodingError,
    YinjieErrorPolicy,
    YinjiePathContext,
    YinjiePathStage,
    YinjieReportingPolicy,
    yinjie_error_policy,
    yinjie_cli_policy,
    yinjie_reporting_policy,
)


class TestYinjieSetupStages(unittest.TestCase):
    def test_composition_root_returns_default_singletons_and_runner(self):
        runner = create_default_application_runner()

        self.assertIs(get_default_error_policy(), yinjie_error_policy)
        self.assertIs(get_default_reporting_policy(), yinjie_reporting_policy)
        self.assertIs(get_default_cli_policy(), yinjie_cli_policy)
        self.assertIsInstance(create_default_encoder(), YinjieEncoder)
        self.assertIsInstance(runner, YinjieApplicationRunner)
        self.assertIs(runner.cli_policy, yinjie_cli_policy)

    def test_composition_root_runs_interactive_session_with_default_dependencies(self):
        captured = {}

        def interactive_entry(**kwargs):
            captured.update(kwargs)

        run_default_interactive_session(
            input_reader=lambda prompt: "q",
            interactive_entry=interactive_entry,
        )

        self.assertIs(captured["cli_policy"], yinjie_cli_policy)
        self.assertIs(captured["encoder_factory"], create_default_encoder)
        self.assertTrue(callable(captured["input_reader"]))

    def test_application_runner_routes_success_to_cli_policy(self):
        outputs = []

        class StubEncoder:
            def encode_all_yinjie(self):
                return Path("output.json")

        policy = YinjieCliPolicy(output_writer=outputs.append, exit_handler=lambda code: None)
        runner = YinjieApplicationRunner(encoder_factory=StubEncoder, cli_policy=policy)

        runner.run_main()

        self.assertEqual(outputs, ["编码文件已生成: output.json"])

    def test_application_runner_routes_failure_to_cli_policy(self):
        exit_codes = []

        class FailingEncoder:
            def encode_all_yinjie(self):
                raise YinjieEncodingError("失败消息", stage="batch")

        policy = YinjieCliPolicy(
            output_writer=lambda message: None,
            exit_handler=exit_codes.append,
        )
        runner = YinjieApplicationRunner(encoder_factory=FailingEncoder, cli_policy=policy)

        with self.assertRaises(SystemExit):
            runner.run_main()

        self.assertEqual(exit_codes, [1])

    def test_cli_policy_routes_terminal_output_and_exit(self):
        outputs = []
        exit_codes = []

        def output_writer(message: str) -> None:
            outputs.append(message)

        def exit_handler(code: int) -> None:
            exit_codes.append(code)

        policy = YinjieCliPolicy(output_writer=output_writer, exit_handler=exit_handler)

        policy.main_success(Path("output.json"))
        policy.interactive_banner()
        policy.interactive_empty_input()
        policy.interactive_result("ABCD")
        policy.interactive_known_error(YinjieEncodingError("错误消息", stage="input"))
        policy.interactive_unexpected_error(RuntimeError("异常消息"))

        with self.assertRaises(SystemExit):
            policy.main_failure(RuntimeError("主流程失败"))

        self.assertEqual(exit_codes, [1])
        self.assertEqual(
            outputs,
            [
                "编码文件已生成: output.json",
                "拼音编码交互工具 (输入q退出)",
                "输入不能为空",
                "编码结果: ABCD\n",
                "错误: 错误消息",
                "发生意外错误: 异常消息",
            ],
        )

    def test_reporting_policy_emits_expected_messages(self):
        class StubLogger:
            def __init__(self):
                self.warning_calls = []
                self.info_calls = []
                self.error_calls = []

            def warning(self, message, *args):
                self.warning_calls.append(message % args)

            def info(self, message, *args):
                self.info_calls.append(message % args)

            def error(self, message, *args):
                self.error_calls.append(message % args)

        logger = StubLogger()
        policy = YinjieReportingPolicy()

        policy.ignored_output_subdir(logger, "ignored-subdir")
        policy.syllable_encoding_failure(logger, "bad1", "模拟失败")
        policy.output_generated(logger, Path("output.json"))
        policy.program_failure(logger, RuntimeError("程序失败"))

        self.assertEqual(
            logger.warning_calls,
            [
                "已忽略 output_subdir='ignored-subdir'；当前使用统一输出路径。",
                "音节 'bad1' 编码失败: 模拟失败",
            ],
        )
        self.assertEqual(logger.info_calls, ["成功生成编码文件: output.json"])
        self.assertEqual(logger.error_calls, ["程序执行失败: 程序失败"])

    def test_error_policy_builds_batch_failure_contract(self):
        error = yinjie_error_policy.batch_failure([("bad1", "模拟失败")])

        self.assertIsInstance(error, YinjieEncodingError)
        self.assertEqual(error.stage, "batch")
        self.assertEqual(error.failures, [("bad1", "模拟失败")])
        self.assertIn("bad1: 模拟失败", str(error))

    def test_error_policy_builds_syllable_failure_contract(self):
        policy = YinjieErrorPolicy()

        error = policy.syllable_failure("split", "hm1", "切分失败")

        self.assertEqual(error.stage, "split")
        self.assertEqual(error.syllable, "hm1")
        self.assertEqual(error.detail, "切分失败")
        self.assertIn("音节 'hm1' 在 split 阶段失败: 切分失败", str(error))

    def test_project_root_stage_finds_workspace_root(self):
        stage = ProjectRootStage()
        base_dir = Path(__file__).resolve().parent / "syllable" / "analysis" / "slice"

        self.assertEqual(stage.run(base_dir), Path(__file__).resolve().parent)

    def test_path_stage_resolves_input_and_output_paths(self):
        calls = []

        def validator(path: Path) -> Path:
            calls.append(path)
            return path

        project_root = Path(__file__).resolve().parent
        stage = YinjiePathStage(validator, "yinjie_code.json")

        result = stage.run(project_root, "ignored-subdir")

        self.assertEqual(
            result,
            YinjiePathContext(
                project_root=project_root,
                input_path=project_root / "pinyin" / "hanzi_pinyin" / "pinyin_normalized.json",
                output_path=project_root / "yinjie_code.json",
            ),
        )
        self.assertEqual(
            calls,
            [project_root / "pinyin" / "hanzi_pinyin" / "pinyin_normalized.json"],
        )

    def test_path_stage_uses_reporting_policy_for_ignored_subdir(self):
        class StubReportingPolicy:
            def __init__(self):
                self.calls = []

            def ignored_output_subdir(self, stage_logger, output_subdir):
                self.calls.append((stage_logger, output_subdir))

        policy = StubReportingPolicy()
        stage = YinjiePathStage(lambda path: path, "yinjie_code.json", reporting_policy=policy)

        output_path = stage.resolve_output_path(Path("root"), "ignored-subdir")

        self.assertEqual(output_path, Path("root") / "yinjie_code.json")
        self.assertEqual(len(policy.calls), 1)
        self.assertEqual(policy.calls[0][1], "ignored-subdir")

    def test_json_file_repository_round_trip(self):
        repository = JsonFileRepository()
        payload = {"ma1": "code"}

        with tempfile.TemporaryDirectory() as temp_dir:
            file_path = Path(temp_dir) / "data.json"
            repository.save(file_path, payload)

            self.assertEqual(repository.load(file_path), payload)

    def test_encoder_json_methods_delegate_to_repository(self):
        class StubJsonRepository:
            def __init__(self):
                self.load_calls = []
                self.save_calls = []

            def load(self, path: Path):
                self.load_calls.append(path)
                return {"ma1": "code"}

            def save(self, path: Path, data):
                self.save_calls.append((path, data))

        encoder = YinjieEncoder()
        repository = StubJsonRepository()
        encoder.json_repository = repository

        self.assertEqual(encoder._load_json(Path("input.json")), {"ma1": "code"})
        encoder._save_json(Path("output.json"), {"ma1": "code"})
        self.assertEqual(repository.load_calls, [Path("input.json")])
        self.assertEqual(
            repository.save_calls,
            [(Path("output.json"), {"ma1": "code"})],
        )


class TestInteractiveEncoder(unittest.TestCase):
    def test_interactive_encoder_handles_empty_input_result_and_quit(self):
        outputs = []
        prompts = []
        inputs = iter(["", "ma1", "q"])

        class StubEncoder:
            def encode_single_yinjie(self, syllable: str) -> str:
                return "ABCD"

        policy = YinjieCliPolicy(output_writer=outputs.append, exit_handler=lambda code: None)

        def input_reader(prompt: str) -> str:
            prompts.append(prompt)
            return next(inputs)

        interactive_encoder(
            cli_policy=policy,
            input_reader=input_reader,
            encoder_factory=StubEncoder,
        )

        self.assertEqual(
            outputs,
            [
                "拼音编码交互工具 (输入q退出)",
                "输入不能为空",
                "编码结果: ABCD\n",
            ],
        )
        self.assertEqual(
            prompts,
            [
                "请输入拼音(带声调，如'zhong1')：",
                "请输入拼音(带声调，如'zhong1')：",
                "请输入拼音(带声调，如'zhong1')：",
            ],
        )

    def test_interactive_encoder_routes_known_and_unknown_errors(self):
        outputs = []
        inputs = iter(["bad1", "oops1", "q"])

        class StubEncoder:
            def encode_single_yinjie(self, syllable: str) -> str:
                if syllable == "bad1":
                    raise YinjieEncodingError("已知错误", stage="input")
                if syllable == "oops1":
                    raise RuntimeError("未知错误")
                return "ABCD"

        policy = YinjieCliPolicy(output_writer=outputs.append, exit_handler=lambda code: None)

        interactive_encoder(
            cli_policy=policy,
            input_reader=lambda prompt: next(inputs),
            encoder_factory=StubEncoder,
        )

        self.assertEqual(
            outputs,
            [
                "拼音编码交互工具 (输入q退出)",
                "错误: 已知错误",
                "发生意外错误: 未知错误",
            ],
        )


class TestYinjieEncodingStages(unittest.TestCase):
    def test_encode_single_yinjie_uses_stages_to_build_final_code(self):
        split_result = SplitSyllableResult(syllable="ma1", shouyin="m", ganyin="a1")

        class StubStage:
            def __init__(self, result):
                self.result = result
                self.calls = []

            def run(self, value):
                self.calls.append(value)
                return self.result

        class StubAssembleStage:
            def __init__(self, result):
                self.result = result
                self.calls = []

            def run(self, shouyin_result, ganyin_result):
                self.calls.append((shouyin_result, ganyin_result))
                return self.result

        split_stage = StubStage(split_result)
        shouyin_stage = StubStage(EncodedComponentResult(syllable="ma1", value="S"))
        ganyin_stage = StubStage(EncodedComponentResult(syllable="ma1", value="ABC"))
        assemble_stage = StubAssembleStage("SABC")

        encoder = YinjieEncoder()
        encoder.split_stage = split_stage
        encoder.shouyin_stage = shouyin_stage
        encoder.ganyin_stage = ganyin_stage
        encoder.assemble_stage = assemble_stage

        self.assertEqual(encoder.encode_single_yinjie("ma1"), "SABC")
        self.assertEqual(split_stage.calls, ["ma1"])
        self.assertEqual(shouyin_stage.calls, [split_result])
        self.assertEqual(ganyin_stage.calls, [split_result])
        self.assertEqual(
            assemble_stage.calls,
            [(shouyin_stage.result, ganyin_stage.result)],
        )

    def test_assemble_stage_rejects_cross_syllable_results(self):
        stage = YinjieAssembleStage()

        with self.assertRaisesRegex(YinjieEncodingError, "音节不一致"):
            stage.run(
                EncodedComponentResult(syllable="ma1", value="S"),
                EncodedComponentResult(syllable="mo1", value="ABC"),
            )

    def test_shouyin_stage_wraps_encoder_exception(self):
        class RaisingShouyinEncoder:
            def encode_shouyin(self, shouyin: str) -> str:
                raise RuntimeError("首音编码异常")

        stage = ShouyinEncodeStage(RaisingShouyinEncoder())

        with self.assertRaisesRegex(YinjieEncodingError, "首音编码异常") as context:
            stage.run(SplitSyllableResult(syllable="ma1", shouyin="m", ganyin="a1"))

        self.assertEqual(context.exception.stage, "shouyin_encode")

    def test_shouyin_stage_rejects_empty_code(self):
        class EmptyShouyinEncoder:
            def encode_shouyin(self, shouyin: str) -> str:
                return ""

        stage = ShouyinEncodeStage(EmptyShouyinEncoder())

        with self.assertRaisesRegex(YinjieEncodingError, "编码为空") as context:
            stage.run(SplitSyllableResult(syllable="ma1", shouyin="m", ganyin="a1"))

        self.assertEqual(context.exception.stage, "shouyin_encode")

    def test_ganyin_stage_wraps_encoder_exception(self):
        class RaisingGanyinEncoder:
            def encode_ganyin(self, ganyin: str) -> str:
                raise RuntimeError("干音编码异常")

        stage = GanyinEncodeStage(RaisingGanyinEncoder())

        with self.assertRaisesRegex(YinjieEncodingError, "干音编码异常") as context:
            stage.run(SplitSyllableResult(syllable="ma1", shouyin="m", ganyin="a1"))

        self.assertEqual(context.exception.stage, "ganyin_encode")

    def test_ganyin_stage_rejects_invalid_code(self):
        class InvalidGanyinEncoder:
            def encode_ganyin(self, ganyin: str) -> str:
                return "AB"

        stage = GanyinEncodeStage(InvalidGanyinEncoder())

        with self.assertRaisesRegex(YinjieEncodingError, "编码无效") as context:
            stage.run(SplitSyllableResult(syllable="ma1", shouyin="m", ganyin="a1"))

        self.assertEqual(context.exception.stage, "ganyin_encode")


class TestYinjieBatchStages(unittest.TestCase):
    def test_batch_encode_stage_uses_reporting_policy_on_failure(self):
        class StubReportingPolicy:
            def __init__(self):
                self.calls = []

            def syllable_encoding_failure(self, stage_logger, syllable, detail):
                self.calls.append((stage_logger, syllable, detail))

        def controlled_encoder(syllable: str) -> str:
            if syllable == "bad1":
                raise ValueError("模拟失败")
            return syllable.upper()

        policy = StubReportingPolicy()
        stage = YinjieBatchEncodeStage(controlled_encoder, reporting_policy=policy)

        with self.assertRaisesRegex(YinjieEncodingError, r"bad1: 模拟失败"):
            stage.run(["ma1", "bad1"])

        self.assertEqual(len(policy.calls), 1)
        self.assertEqual(policy.calls[0][1:], ("bad1", "模拟失败"))

    def test_batch_input_stage_wraps_load_exception(self):
        def raising_loader(path: Path):
            raise RuntimeError("输入加载失败")

        stage = YinjieBatchInputStage()

        with self.assertRaisesRegex(YinjieEncodingError, "输入加载失败") as context:
            stage.run(Path("input.json"), Path("output.json"), raising_loader)

        self.assertEqual(context.exception.stage, "load_input")

    def test_batch_encode_stage_collects_failures(self):
        def controlled_encoder(syllable: str) -> str:
            if syllable == "bad1":
                raise ValueError("模拟失败")
            return syllable.upper()

        stage = YinjieBatchEncodeStage(controlled_encoder)

        with self.assertRaisesRegex(YinjieEncodingError, r"bad1: 模拟失败") as context:
            stage.run(["ma1", "bad1"])

        self.assertEqual(context.exception.stage, "batch")

    def test_batch_output_stage_wraps_save_exception(self):
        def raising_saver(path: Path, data: dict[str, str]) -> None:
            raise RuntimeError("保存失败")

        stage = YinjieBatchOutputStage()

        with self.assertRaisesRegex(YinjieEncodingError, "保存失败") as context:
            stage.run(Path("output.json"), {"ma1": "code"}, raising_saver)

        self.assertEqual(context.exception.stage, "save_output")

    def test_batch_output_stage_uses_reporting_policy_on_success(self):
        class StubReportingPolicy:
            def __init__(self):
                self.calls = []

            def output_generated(self, stage_logger, output_path):
                self.calls.append((stage_logger, output_path))

        captured = {}

        def saver(path: Path, data: dict[str, str]) -> None:
            captured["saved"] = (path, data)

        policy = StubReportingPolicy()
        stage = YinjieBatchOutputStage(reporting_policy=policy)

        result = stage.run(Path("output.json"), {"ma1": "code"}, saver)

        self.assertEqual(result, Path("output.json"))
        self.assertEqual(captured["saved"], (Path("output.json"), {"ma1": "code"}))
        self.assertEqual(len(policy.calls), 1)
        self.assertEqual(policy.calls[0][1], Path("output.json"))

    def test_encode_all_yinjie_uses_setup_and_batch_stages(self):
        class StubPathStage:
            def __init__(self, result):
                self.result = result
                self.calls = []

            def run(self, project_root, output_subdir):
                self.calls.append((project_root, output_subdir))
                return self.result

        class StubInputStage:
            def __init__(self, result):
                self.result = result
                self.calls = []

            def run(self, input_path, output_path, loader):
                self.calls.append((input_path, output_path, loader))
                return self.result

        class StubBatchEncodeStage:
            def __init__(self, result):
                self.result = result
                self.calls = []

            def run(self, yinjie_list):
                self.calls.append(yinjie_list)
                return self.result

        class StubBatchOutputStage:
            def __init__(self, result):
                self.result = result
                self.calls = []

            def run(self, output_path, data, saver):
                self.calls.append((output_path, data, saver))
                return self.result

        encoder = YinjieEncoder()
        path_context = YinjiePathContext(
            project_root=Path("controlled-root"),
            input_path=Path("controlled-input.json"),
            output_path=Path("controlled-output.json"),
        )
        batch_input = BatchInputResult(
            input_path=Path("controlled-input.json"),
            output_path=Path("controlled-output.json"),
            yinjie_list=["ma1"],
        )
        path_stage = StubPathStage(path_context)
        input_stage = StubInputStage(batch_input)
        encode_stage = StubBatchEncodeStage({"ma1": "code"})
        output_stage = StubBatchOutputStage(Path("final-output.json"))

        encoder.project_root = Path("controlled-root")
        encoder.path_stage = path_stage
        encoder.batch_input_stage = input_stage
        encoder.batch_encode_stage = encode_stage
        encoder.batch_output_stage = output_stage

        self.assertEqual(encoder.encode_all_yinjie("yinyuan"), Path("final-output.json"))
        self.assertEqual(path_stage.calls, [(Path("controlled-root"), "yinyuan")])
        self.assertEqual(
            input_stage.calls,
            [(Path("controlled-input.json"), Path("controlled-output.json"), encoder._load_json)],
        )
        self.assertEqual(encode_stage.calls, [["ma1"]])
        self.assertEqual(
            output_stage.calls,
            [(Path("controlled-output.json"), {"ma1": "code"}, encoder._save_json)],
        )


if __name__ == '__main__':
    unittest.main()

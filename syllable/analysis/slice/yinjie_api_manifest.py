"""音节编码模块的分层 API 导出清单。"""

YINJIE_IMPLEMENTATION_EXPORTS = [
    "BatchInputResult",
    "EncodedComponentResult",
    "GanyinEncodeStage",
    "JsonFileRepository",
    "ProjectRootStage",
    "ShouyinEncodeStage",
    "SplitSyllableResult",
    "YinjieApplicationRunner",
    "YinjieAssembleStage",
    "YinjieBatchEncodeStage",
    "YinjieBatchInputStage",
    "YinjieBatchOutputStage",
    "YinjieCliPolicy",
    "YinjieEncoder",
    "YinjieEncodingError",
    "YinjieErrorPolicy",
    "YinjiePathContext",
    "YinjiePathStage",
    "YinjieReportingPolicy",
    "logger",
    "main",
    "yinjie_cli_policy",
    "yinjie_error_policy",
    "yinjie_reporting_policy",
]

YINJIE_COMPOSITION_EXPORTS = [
    "create_default_application_runner",
    "create_default_encoder",
    "get_default_cli_policy",
    "get_default_error_policy",
    "get_default_reporting_policy",
    "run_default_interactive_session",
]

YINJIE_FACADE_EXPORTS = [
    *YINJIE_IMPLEMENTATION_EXPORTS,
    *YINJIE_COMPOSITION_EXPORTS,
]

YINJIE_ROOT_ENTRY_EXPORTS = YINJIE_FACADE_EXPORTS

YINJIE_INTERACTIVE_ENTRY_EXPORTS = [
    "interactive_encoder",
    "main",
]

__all__ = [
    "YINJIE_COMPOSITION_EXPORTS",
    "YINJIE_FACADE_EXPORTS",
    "YINJIE_INTERACTIVE_ENTRY_EXPORTS",
    "YINJIE_IMPLEMENTATION_EXPORTS",
    "YINJIE_ROOT_ENTRY_EXPORTS",
]

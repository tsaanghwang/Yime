"""音节编码应用的默认装配根。"""

from collections.abc import Callable

try:
    from . import yinjie_encoder as _encoder_impl
except ImportError:
    import yinjie_encoder as _encoder_impl


def get_default_error_policy() -> _encoder_impl.YinjieErrorPolicy:
    return _encoder_impl.yinjie_error_policy


def get_default_reporting_policy() -> _encoder_impl.YinjieReportingPolicy:
    return _encoder_impl.yinjie_reporting_policy


def get_default_cli_policy() -> _encoder_impl.YinjieCliPolicy:
    return _encoder_impl.yinjie_cli_policy


def create_default_encoder() -> _encoder_impl.YinjieEncoder:
    return _encoder_impl.YinjieEncoder()


def create_default_application_runner(
    cli_policy: _encoder_impl.YinjieCliPolicy | None = None,
) -> _encoder_impl.YinjieApplicationRunner:
    return _encoder_impl.YinjieApplicationRunner(
        encoder_factory=create_default_encoder,
        cli_policy=cli_policy or get_default_cli_policy(),
    )


def main(cli_policy: _encoder_impl.YinjieCliPolicy | None = None) -> None:
    create_default_application_runner(cli_policy=cli_policy).run_main()


def run_default_interactive_session(
    input_reader: Callable[[str], str] = input,
    interactive_entry: Callable[..., None] | None = None,
) -> None:
    if interactive_entry is None:
        try:
            from .interactive_yinjie_session import interactive_encoder as interactive_entry
        except ImportError:
            from interactive_yinjie_session import interactive_encoder as interactive_entry

    interactive_entry(
        cli_policy=get_default_cli_policy(),
        input_reader=input_reader,
        encoder_factory=create_default_encoder,
    )


__all__ = [
    "create_default_application_runner",
    "create_default_encoder",
    "get_default_cli_policy",
    "get_default_error_policy",
    "get_default_reporting_policy",
    "main",
    "run_default_interactive_session",
]

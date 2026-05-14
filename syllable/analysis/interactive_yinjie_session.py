"""交互式音节编码会话实现。"""

from collections.abc import Callable

try:
    from .yinjie_encoder import YinjieCliPolicy, YinjieEncoder, YinjieEncodingError
    from .yinjie_composition import create_default_encoder, get_default_cli_policy
except ImportError:
    from yinjie_encoder import YinjieCliPolicy, YinjieEncoder, YinjieEncodingError
    from yinjie_composition import create_default_encoder, get_default_cli_policy


def interactive_encoder(
    cli_policy: YinjieCliPolicy | None = None,
    input_reader: Callable[[str], str] = input,
    encoder_factory: Callable[[], YinjieEncoder] | None = None,
) -> None:
    """运行交互式拼音编码会话。"""
    cli_policy = cli_policy or get_default_cli_policy()
    encoder_factory = encoder_factory or create_default_encoder
    encoder = encoder_factory()
    cli_policy.interactive_banner()

    while True:
        try:
            pinyin = input_reader("请输入拼音(带声调，如'zhong1')：").strip()
            if pinyin.lower() == 'q':
                break

            if not pinyin:
                cli_policy.interactive_empty_input()
                continue

            code = encoder.encode_single_yinjie(pinyin)
            cli_policy.interactive_result(code)

        except YinjieEncodingError as error:
            cli_policy.interactive_known_error(error)
        except Exception as error:
            cli_policy.interactive_unexpected_error(error)


__all__ = ["interactive_encoder"]

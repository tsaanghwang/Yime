"""核心模块：解码器、键盘监听、输入管理"""

from .char_code_index import CharCodeCandidate, CharCodeIndex
from .decoders import StaticCandidateDecoder, RuntimeCandidateDecoder, CompositeCandidateDecoder
from .keyboard_listener import KeyboardListener
from .input_manager import InputManager, InputState
from .prefix_tree import PrefixTree

__all__ = [
    "CharCodeCandidate",
    "CharCodeIndex",
    "StaticCandidateDecoder",
    "RuntimeCandidateDecoder",
    "CompositeCandidateDecoder",
    "KeyboardListener",
    "InputManager",
    "InputState",
    "PrefixTree",
]

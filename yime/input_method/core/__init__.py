"""核心模块：解码器、键盘监听、输入管理"""

from .decoders import StaticCandidateDecoder, RuntimeCandidateDecoder, CompositeCandidateDecoder

__all__ = [
    "StaticCandidateDecoder",
    "RuntimeCandidateDecoder",
    "CompositeCandidateDecoder",
]

"""
syllable.analysis.slice 包初始化文件
导出干音分析相关类
"""

from importlib import import_module
import sys


_MOVED_MODULES = [
	"Syllable",
	"final_categorizer",
	"ganyin",
	"ganyin_categorizer",
	"ganyin_encoder",
	"interactive_yinjie_session",
	"pianyin",
	"pitched_pianyin",
	"pitched_yinyuan",
	"shouyin",
	"shouyin_encoder",
	"slicer",
	"syllable_analyzer",
	"syllable_categorizer",
	"syllable_encoding_pipeline",
	"syllable_segmenter",
	"syllable_splitter",
	"unpitched_pianyin",
	"yinjie_api_manifest",
	"yinjie_composition",
	"yinjie_encoder",
	"yinyuan",
	"yueyin_yinyuan",
	"zaoyin_yinyuan",
]


for _module_name in _MOVED_MODULES:
	_module = import_module(f"syllable.analysis.{_module_name}")
	sys.modules[f"{__name__}.{_module_name}"] = _module


del _module
del _module_name


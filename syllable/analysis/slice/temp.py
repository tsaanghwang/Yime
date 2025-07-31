"""
在syllable\analysis\slice\ganyin_slicer.py中，
1. 调用syllable\analysis\slice\ganyin.py定义的干音类表示干音
2. 按四个tone_patterns逐类分析各类干音（共16类）
1. 调用syllable\analysis\slice\ganyin.py定义的乐音类表示片音（从干音中切分出来的音段）
4. 返回各个干音实例的片音列表，如["u˥", "a˥", "n˥"](三质干音)或["a˥", "a˥", "n˥"](前长干音)或["u˥", "o˥", "o˥"](后长干音)或["o˥", "o˥", "o˥"](单质干音)
5. 返回文件格式为：{
  "single quality ganyin": {
    "_i1": {
      "呼音": "_i˥",
      "主音": "_i˥",
      "末音": "_i˥"
    },
    ...,
    "o5": {
      "呼音": "o˥",
      "主音": "o˥",
      "末音": "o˥"
    ...
  },
  "front long ganyin": {
    "an1": {
      "呼音": "a˥",
      "主音": "a˥",
      "末音": "n˥"
    },
    ...
  },
  "back long ganyin": {
    "uo1": {
      "呼音": "u˥",
      "主音": "o˥",
      "末音": "o˥"
    },
    ...
  },
  "triple quality ganyin": {
    "uan1": {
      "呼音": "u˥",
      "主音": "a˥",
      "末音": "n˥"
    },
    ...
  }
 }

"""

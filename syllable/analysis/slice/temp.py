"""
  在syllable\analysis\slice\shouyin_encoder.py中，
  检查在生成的文件syllable\analysis\slice\yinyuan\yinyuan.json中
出现      "z": "􀀀",
      "h": "􀀁"
    },
    {
      "c": "􀀀",
      "h": "􀀁"
    },
    {
      "s": "􀀀",
      "h": "􀀁"
    },
也就是说，检查字典的键"zh", "ch", "sh"分别被分成两个键"z", "h"；"c", "h"；"s", "h"的
的元音，把它们按一个键"zh", "ch", "sh"处理。
"""

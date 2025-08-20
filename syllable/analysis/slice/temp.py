"""
  在syllable\analysis\slice\generate_zaoyin_yinyuan.py中，更改输出文件结构：
把当前结构：
    result = {
        "name": {"Indeterminate Pitch Yinyuan": "不定调音元或噪音类音元"},
        "description": "由 ClearNoise和VoicedNoise 两类音元组成",
        "unpitched_yinyuan": {},
        "unstable_pitch_yinyuan": {},
        "codes": {}
    }

改为：
    result = {
        "name": {"Indeterminate Pitch Yinyuan": "不定调音元或噪音类音元"},
        "description": "由 ClearNoise和VoicedNoise 两类音元组成",
        indeterminate_pitch_yinyuan: {
        "unpitched_yinyuan": {},
        "unstable_pitch_yinyuyuan": {},
        "codes": {}
        },
        并修改相应代码
  """

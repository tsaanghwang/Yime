"""
提取乐音类片音
功能：从被切分成乐音序列的干音中提取乐音类片音
输入：干音数据（JSON格式）
输出：提取的乐音类片音数据（JSON格式）
{
  "i˥": "i5",
  "i˦": "i4",
  "i˧": "i3",
  "i˨": "i2",
  "i˩": "i1",
  "ɪ˥": "ɪ5",
  "ɪ˦": "ɪ4",
  "ɪ˧": "ɪ3",
  "ɪ˨": "ɪ2",
  "ɪ˩": "ɪ1",
  "u˥": "u5",
  "u˦": "u4",
  "u˧": "u3",
  "u˨": "u2",
  "u˩": "u1",
    ...
}
"""

import json
from pathlib import Path

def extract_yueyin(input_path, output_path):
    with open(input_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    
    yueyin_map = {}
    
    # 处理所有干音类别
    for category in data.values():
        for sound_data in category.values():
            # 提取呼音、主音和末音
            for sound_type in ["呼音", "主音", "末音"]:
                sound = sound_data[sound_type]
                
                # 处理可能的分隔符"/"
                for variant in sound.split("/"):
                    # 提取音素和声调
                    if "˥" in variant:
                        tone = "5"
                        phoneme = variant.split("˥")[0]
                    elif "˦" in variant:
                        tone = "4"
                        phoneme = variant.split("˦")[0]
                    elif "˧" in variant:
                        tone = "3"
                        phoneme = variant.split("˧")[0]
                    elif "˨" in variant:
                        tone = "2"
                        phoneme = variant.split("˨")[0]
                    elif "˩" in variant:
                        tone = "1"
                        phoneme = variant.split("˩")[0]
                    else:
                        continue  # 忽略无声调的音素
                    
                    # 构建乐音类片音映射
                    key = f"{phoneme}˥" if tone == "5" else \
                          f"{phoneme}˦" if tone == "4" else \
                          f"{phoneme}˧" if tone == "3" else \
                          f"{phoneme}˨" if tone == "2" else \
                          f"{phoneme}˩"
                    
                    value = f"{phoneme}{tone}"
                    yueyin_map[key] = value
    
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(yueyin_map, f, ensure_ascii=False, indent=2)

if __name__ == "__main__":
    base_dir = Path(__file__).parent
    input_path = base_dir / "ganyin_slicer_output.json"
    output_path = base_dir / "pitched_pianyin.json"
    extract_yueyin(input_path, output_path)
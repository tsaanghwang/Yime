"""
多音词YAML到JSON转换器
功能：
1. 将YAML文件中的汉字-拼音对转换为JSON格式
2. 处理重复汉字的情况，合并拼音列表
3. 输入格式：
    # 存在重复键的yaml结构的多音字对照表格式示例：
    不臊 bu2 sao4
    不自在 bu2 zi4 zai4
    不自在 bu2 zi4 zai5

4. 输出格式：
{
  "不臊": ["bu2 sao4"],
  "不自在": [
    "bu2 zi4 zai4",
    "bu2 zi4 zai5"
  ]
}

5. 使用绝对路径：
输入YAML文件路径：pinyin/hanzi_pinyin/duozi_pinyin.yaml
输出JSON文件路径：pinyin/hanzi_pinyin/duozi_pinyin.json
"""

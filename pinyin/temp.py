# 在pinyin\hanzi_pinyin\pinyin_normalizer.py中，直接按TONE_POSITION_PRIORITY列表
# 定义的顺序查找标调位置并标调过于粗糙，需要修改标调规则：
  # 对有['a', 'o', 'e']的拼音按['a', 'o', 'e']的顺序标调
  # 对没有['a', 'o', 'e']的拼音：
    # 在含有['iu', 'ui']的拼音中调号标在后一字符上
    # 否则把调号标在['i', 'u', 'v', 'ü']上
# 请按照以上规则修改标调逻辑

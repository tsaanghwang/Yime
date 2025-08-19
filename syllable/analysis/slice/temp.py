"""
  在syllable\analysis\slice\shouyin_analyzer.py中，更改处理逻辑：
  1. 从shouyin_analyzer.py中添加一个函数或更改当前函数
  2. 在函数中调用dict=GanyinCategorizer.generate_shouyin_data(pinyin_data)方法，生成shouyin_data字典
  3. 从输入的initial_ipa字典中读取声母对应的的音标
  4. 当shouyin_data字典的key与initial_ipa字典的key相同时，用后者的的值替换shouyin_data字典的value
  5. 返回shouyin_data字典并按现有逻辑写入pianyin_initial.json文件

  """

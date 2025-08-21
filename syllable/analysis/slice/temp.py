"""
  在syllable\analysis\slice\shouyin_encoder.py中，修改105-110行：
  "        # 2. 生成音元序列数据
        input_file = base_dir / 'yinyuan' / 'shouyin.json'
        output_file = base_dir / 'yinyuan' / 'shouyin_to_yinyuan.json'
        shouyin_data = self.load_shouyin_data(input_file)
        yinyuan_data = self.process_shouyin(shouyin_data)
        self.save_yinyuan_data(output_file, yinyuan_data)
"
改成:
1. 调用process_shouyin函数获得返回数据:
{"首音": ["shouyin1", "shouyin2", ...]}
2. 调用map_shouyin_to_codepoint函数获得字典{"首音": ["shouyin1", "shouyin2", ...]}中的
首音列表["shouyin1", "shouyin2", ...]终端首音对应的codepoint，并以shouyin作为key，codepoint
作为value，存入字典{"首音": ["shouyin1"： "codepoint1", ...]}中
  """

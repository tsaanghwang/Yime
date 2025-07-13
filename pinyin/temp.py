# 在pinyin目录下，添加模块：“merge_duplicate_keys.py"，定义“merge_duplicate_keys(yaml_data, mode="single-char")”，合并“pinyin/ danzi_pinyin.yaml”的所有重复key（汉字单字）条目，保留所合并的键（汉字）的不同值（带调拼音），并把合并后的数据转换成一个json文件。
# 另一模式是：mode=“multi-char”，合并“pinyin/ duozi_pinyin.yaml”的所有重复key（汉字字组）条目，保留所有重复键（双字和多字字组）的重复值（带调拼音），并把合并后的数据转换成另一个json文件。
# 由于读写文件数据过大，分布先写第一种模式。第二次请求，再写第二种模式。

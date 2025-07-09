import pandas as pd

# 读取 Excel 文件 - 使用原始字符串处理Windows路径
file_path = r'C:\Users\Freeman Golden\.inscode-tutor\InsCode-Tutor\Yinyuanxitong\syllable\字符顺序表.xlsx'
df = pd.read_excel(file_path, sheet_name='Sheet1')

# 输出 DataFrame 内容
print(df)

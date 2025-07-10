# syllable/analysis/onset_rhyme/generate_onset_rhyme.py
from helper import OnsetRhymeAnalysisHelper
import json


def main():
    helper = OnsetRhymeAnalysisHelper()
    success = helper.analyze_pinyin_file()

    if success:
        print("成功生成 onset_rhyme.json 文件")
        # 读取并打印生成的文件内容
        with open(helper.output_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
            print("生成的文件内容示例：")
            for onset, rhymes in list(data.items())[:5]:  # 只打印前5项作为示例
                print(f"{onset}: {rhymes[:5]}...")  # 每项只打印前5个韵母
    else:
        print("生成 onset_rhyme.json 文件失败")


if __name__ == "__main__":
    main()

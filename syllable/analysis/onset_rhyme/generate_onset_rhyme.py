# syllable/analysis/onset_rhyme/generate_onset_rhyme.py
from helper import OnsetRhymeAnalysisHelper
import json
import argparse
import logging


def setup_logging():
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )


def main(input_path=None, output_path=None):
    helper = OnsetRhymeAnalysisHelper()
    if input_path:
        helper.input_path = input_path
    if output_path:
        helper.output_path = output_path

    logging.info("开始声韵分析...")
    success = helper.analyze_pinyin_file()

    if success:
        logging.info(f"成功生成 {helper.output_path}")
        try:
            with open(helper.output_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
                logging.info(f"共生成 {len(data)} 个声母条目")
                for onset, rhymes in list(data.items())[:5]:
                    logging.info(f"{onset}: 包含 {len(rhymes)} 个韵母")
        except Exception as e:
            logging.error(f"读取结果文件失败: {e}")
    else:
        logging.error("生成 onset_rhyme.json 文件失败")


if __name__ == "__main__":
    setup_logging()
    parser = argparse.ArgumentParser(description='声韵分析生成工具')
    parser.add_argument('--input', help='输入文件路径')
    parser.add_argument('--output', help='输出文件路径')
    args = parser.parse_args()

    main(input_path=args.input, output_path=args.output)

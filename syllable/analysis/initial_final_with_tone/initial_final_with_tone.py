# syllable/analysis/initial_final_with_tone/initial_final_with_tone.py
from analysis_executor import InitialFinalWithToneAnalysisExecutor
import json
import argparse
import logging


def setup_logging():
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )


def main(input_path=None, output_path=None):
    analysis_executor = InitialFinalWithToneAnalysisExecutor()
    if input_path:
        analysis_executor.input_path = input_path
    if output_path:
        analysis_executor.output_path = output_path

    logging.info("开始声母韵母声调分析...")
    success = analysis_executor.analyze_pinyin_file()

    if success:
        logging.info(f"成功生成 {analysis_executor.output_path}")
        try:
            with open(analysis_executor.output_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
                logging.info(f"共生成 {len(data)} 个声母条目")
                for initial, final_with_tone_items in list(data.items())[:5]:
                    logging.info(f"{initial}: 包含 {len(final_with_tone_items)} 个韵母")
        except Exception as e:
            logging.error(f"读取结果文件失败: {e}")
    else:
        logging.error("生成 initial_final_with_tone.json 文件失败")


if __name__ == "__main__":
    setup_logging()
    parser = argparse.ArgumentParser(description='声母韵母声调分析生成工具')
    parser.add_argument('--input', help='输入文件路径')
    parser.add_argument('--output', help='输出文件路径')
    args = parser.parse_args()

    main(input_path=args.input, output_path=args.output)

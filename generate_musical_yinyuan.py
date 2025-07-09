# yinyuan/generate_pitched_yinyuan.py
import json
from yinyuan.pitched_yinyuan import PitchedYinyuan


def generate_pitched_yinyuan():
    """生成乐音类音元数据"""
    yinyuan = PitchedYinyuan()

    with open('yinyuan/pitched_pianyin.json', 'r', encoding='utf-8') as f:
        input_data = json.load(f)

    converted_data = {key: [key[:-1], key[-1]] for key in input_data.keys()}

    # 直接使用PitchedYinyuan类的方法
    output_dynamic_tonal_elements_model = yinyuan.process_pitched_yinyuan(
        converted_data, False)
    output_isochronous_tonal_elements_model = yinyuan.process_pitched_yinyuan(
        converted_data, True)

    # 保存结果
    with open('yinyuan/pitched_yinyuan_of_dynamic_model.json', 'w', encoding='utf-8') as f:
        json.dump(output_dynamic_tonal_elements_model,
                  f, ensure_ascii=False, indent=2)

    with open('pitched_yinyuan_of_isochronous_model.json', 'w', encoding='utf-8') as f:
        json.dump(output_isochronous_tonal_elements_model,
                  f, ensure_ascii=False, indent=2)

    print("处理完成，结果已保存到:")
    print("- yinyuan/pitched_yinyuan_of_dynamic_model.json")
    print("- yinyuan/pitched_yinyuan_of_isochronous_model.json")


if __name__ == '__main__':
    generate_pitched_yinyuan()

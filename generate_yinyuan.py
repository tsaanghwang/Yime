import json
from collections import defaultdict
from pathlib import Path
from yinyuan import UnpitchedYinyuan, PitchedYinyuan


def generate_unpitched_yinyuan():
    # 1. 加载原始数据
    with open('pianyin/pianyin_initial.json', 'r', encoding='utf-8') as f:
        unpitched_pianyin = json.load(f)

    # 从 JSON 中获取声母排列顺序
    INITIAL_ORDER = unpitched_pianyin.get('initial_order', [
        'b', 'p', 'm', 'f',
        'd', 't', 'n', 'l',
        'g', 'k', 'h',
        'j', 'q', 'x',
        'zh', 'ch', 'sh', 'r',
        'z', 'c', 's'
    ])

    # 2. 创建新的数据结构
    yinyuan_data = {
        "name": "噪音类音元",
        "description": "噪音类音元是噪音类片音的另一种符号化表示形式",
        "note": "暂时借用表示声母的符号表示噪音类音元，以便理解。零声母[ŋ, ʔ, ɣ]用隔音符号/'(U+0027)/来表示，在音节界限不发生混淆时省略，只在音节界限发生混淆时标注。",
        "unpitched_yinyuan": {},
        "codes": {}  # 新增音元代码映射
    }

    # 3. 合并清音和浊音，反转键值映射
    merged_mapping = defaultdict(list)

    def get_initial(initial):
        """获取拼音的声母部分"""
        # 先检查双字母声母(zh, ch, sh)
        if initial.startswith('zh'):
            return 'zh'
        elif initial.startswith('ch'):
            return 'ch'
        elif initial.startswith('sh'):
            return 'sh'
        # 然后检查单字母声母
        elif initial[0] in INITIAL_ORDER:
            return initial[0]
        else:
            return ''  # 无标准声母的情况

    # 处理清音
    for ipa, initial_list in unpitched_pianyin['unpitched_pianyin']['voiceless'].items():
        for initial in initial_list:
            merged_mapping[initial].append(ipa)

    # 处理浊音
    for ipa, initial_list in unpitched_pianyin['unpitched_pianyin']['voiced'].items():
        for initial in initial_list:
            merged_mapping[initial].append(ipa)

    # 4. 按声母排列顺序排序
    sorted_initial = sorted(merged_mapping.keys(),
                            key=lambda x: (INITIAL_ORDER.index(get_initial(x))
                                           if get_initial(x) in INITIAL_ORDER
                                           else len(INITIAL_ORDER), x))

    for initial in sorted_initial:
        yinyuan_data['unpitched_yinyuan'][initial] = merged_mapping[initial]
        # 为每个拼音生成音元代码
        code = UnpitchedYinyuan._get_yinyuan_code(initial)
        if code is not None:
            yinyuan_data['codes'][initial] = code

    # 5. 写入输出文件
    output_path = 'yinyuan/unpitched_yinyuan.json'
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)  # 确保目录存在
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(yinyuan_data, f, ensure_ascii=False, indent=2)

    print(f"成功生成噪音类音元文件: {output_path}")
    print(f"共生成 {len(yinyuan_data['unpitched_yinyuan'])} 个噪音类音元")

    return yinyuan_data


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

    with open('yinyuan/pitched_yinyuan_of_isochronous_model.json', 'w', encoding='utf-8') as f:
        json.dump(output_isochronous_tonal_elements_model,
                  f, ensure_ascii=False, indent=2)

    print("处理完成，结果已保存到:")
    print("- yinyuan/pitched_yinyuan_of_dynamic_model.json ")
    print("- yinyuan/pitched_yinyuan_of_isochronous_model.json")


def prompt_user_choice():
    """交互式终端提示用户选择音元类型"""
    print("\n请选择要生成的音元类型:")
    print("1. 噪音类音元")
    print("2. 乐音类音元")
    print("3. 同时生成两类音元")
    print("4. 退出")

    while True:
        choice = input("请输入选项(1-4): ").strip()
        if choice == '1':
            return 'unpitched_yinyuan'
        elif choice == '2':
            return 'pitched_yinyuan'
        elif choice == '3':
            return 'all'
        elif choice == '4':
            return 'exit'
        else:
            print("无效输入，请重新选择")


def main(yinyuan_type=None):
    """根据类型调用相应生成函数"""
    if yinyuan_type is None:
        yinyuan_type = prompt_user_choice()
        if yinyuan_type == 'exit':
            return

    if yinyuan_type == "unpitched_yinyuan":
        return generate_unpitched_yinyuan()
    elif yinyuan_type == "pitched_yinyuan":
        return generate_pitched_yinyuan()
    elif yinyuan_type == "all":
        print("\n正在生成噪音类音元...")
        generate_unpitched_yinyuan()
        print("\n正在生成乐音类音元...")
        generate_pitched_yinyuan()
        print("\n两类音元已全部生成完成")
    else:
        raise ValueError(f"未知音元类型: {yinyuan_type}")


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='生成音元数据')
    parser.add_argument('type', nargs='?', choices=['unpitched_yinyuan', 'pitched_yinyuan', 'all'],
                        help='音元类型(unpitched_yinyuan, pitched_yinyuan或all)')
    args = parser.parse_args()

    main(args.type)

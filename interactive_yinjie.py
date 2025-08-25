# interactive_yinjie.py
from yinjie_encoder import YinjieEncoder

def interactive_encoder():
    """交互式拼音编码工具"""
    encoder = YinjieEncoder()
    print("拼音编码交互工具 (输入q退出)")

    while True:
        try:
            pinyin = input("请输入拼音(带声调，如'zhong1')：").strip()
            if pinyin.lower() == 'q':
                break

            if not pinyin:
                print("输入不能为空")
                continue

            # 调用编码方法
            code = encoder.encode_single_yinjie(pinyin)
            print(f"编码结果: {code}\n")

        except ValueError as e:
            print(f"错误: {str(e)}")
        except Exception as e:
            print(f"发生意外错误: {str(e)}")

if __name__ == "__main__":
    interactive_encoder()
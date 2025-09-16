from import_numeric_pinyin import 数字标调拼音导入器

def 测试导入():
    测试数据 = {
        "zhang1": "",  # 格式兼容旧数据
        "li4": "",
        "wang2": ""
    }

    导入器 = 数字标调拼音导入器()
    try:
        结果 = 导入器.导入数据(测试数据)
        print(f"测试成功，导入{结果}条记录")
    except Exception as e:
        print(f"测试失败: {e}")

if __name__ == "__main__":
    测试导入()
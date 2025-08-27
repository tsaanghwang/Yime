from pathlib import Path

def get_yinjie_json_path():
    module_dir = Path(__file__).parent  # 当前模块目录
    subdir = "yinyuan"                   # 子目录
    filename = "shouyin_yinyuan.json"            # 目标文件
    return module_dir / subdir / filename

# 使用
yinjie_path = get_yinjie_json_path()
print(yinjie_path)
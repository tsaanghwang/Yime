import os
import subprocess
import sys
from pathlib import Path

SCRIPTS_DIR = Path(__file__).parent
WORKSPACE_ROOT = SCRIPTS_DIR.parents[1]


def run(script_name: str, args: list[str] | None = None) -> None:
    script_path = SCRIPTS_DIR / script_name
    cmd = [sys.executable, str(script_path)]
    if args:
        cmd.extend(args)
    print(f"\n{'='*60}")
    print(f"  执行: {script_name} {' '.join(args) if args else ''}")
    print(f"{'='*60}")
    env = os.environ.copy()
    env["PYTHONPATH"] = os.pathsep.join(
        part for part in (str(WORKSPACE_ROOT), env.get("PYTHONPATH", "")) if part
    )
    result = subprocess.run(cmd, cwd=str(SCRIPTS_DIR), env=env)
    if result.returncode != 0:
        print(f"\n[错误] {script_name} 返回码: {result.returncode}")
        raise SystemExit(result.returncode)


def main():
    print("一键构建 hanzi_pinyin 库")
    print("=" * 60)

    run("hanzi_codepoint.py")
    run("hanzi_pinyin.py")
    run("hanzi_frequency.py")
    run("pinyin_source_staging.py")
    run("append_pinyin.py")
    run("export_hanzi_txt.py")

    print(f"\n{'='*60}")
    print("  全部完成！")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()

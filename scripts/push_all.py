# scripts/push_all.py
"""
# 正常推送
python scripts/push_all.py

# 强制推送(谨慎使用)
python scripts/push_all.py -f
"""
import subprocess
import sys
import os
import argparse
from typing import Tuple, Optional


def find_git_root(start_path: str) -> Optional[str]:
    """向上查找git仓库根目录"""
    current_path = os.path.abspath(start_path)
    while True:
        if os.path.exists(os.path.join(current_path, ".git")):
            return current_path
        parent_path = os.path.dirname(current_path)
        if parent_path == current_path:  # 到达文件系统根目录
            return None
        current_path = parent_path


def get_remote_url(remote: str) -> Optional[str]:
    """获取远程仓库URL"""
    try:
        result = subprocess.run(["git", "remote", "get-url", remote],
                                capture_output=True, text=True, check=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return None


def check_branch_status(remote: str, branch: str) -> Tuple[int, int]:
    """检查本地和远程分支的状态差异"""
    try:
        # 检查本地领先多少提交
        ahead = subprocess.run(["git", "rev-list", remote + "/" + branch + "..HEAD", "--count"],
                            capture_output=True, text=True, check=True)
        # 检查本地落后多少提交
        behind = subprocess.run(["git", "rev-list", "HEAD.." + remote + "/" + branch, "--count"],
                                capture_output=True, text=True, check=True)
        return int(ahead.stdout.strip()), int(behind.stdout.strip())
    except subprocess.CalledProcessError as e:
        print(f"检查分支状态失败: {e}")
        return 0, 0


def git_pull(remote: str, branch: str = "main") -> bool:
    """从远程仓库拉取变更"""
    try:
        print(f"正在从 {remote} 仓库拉取 {branch} 分支最新变更...")
        subprocess.run(["git", "fetch", remote, branch], check=True)

        ahead, behind = check_branch_status(remote, branch)

        if behind > 0:
            print(f"本地分支落后 {behind} 个提交，正在合并...")
            subprocess.run(["git", "merge", remote + "/" + branch], check=True)
            print(f"{remote} 拉取并合并成功")
        elif ahead > 0:
            print(f"本地分支领先 {ahead} 个提交，无需拉取")
        else:
            print("本地分支与远程同步，无需拉取")

        return True
    except subprocess.CalledProcessError as e:
        print(f"{remote} 拉取失败: {e}")
        return False


def git_push(remote: str, branch: str = "main", force: bool = False) -> bool:
    """推送代码到远程仓库"""
    try:
        print(f"正在推送代码到 {remote} 仓库...")
        command = ["git", "push", remote, f"{branch}:{branch}"]
        if force:
            command.insert(2, "-f")
            print("警告: 使用强制推送(-f)，这将覆盖远程分支")

        ahead, behind = check_branch_status(remote, branch)
        if behind > 0:
            print(f"错误: 本地分支落后 {behind} 个提交，请先执行 git pull")
            return False

        subprocess.run(command, check=True)
        print(f"{remote} 推送成功")
        return True
    except subprocess.CalledProcessError as e:
        print(f"{remote} 推送失败: {e}")
        if "non-fast-forward" in str(e):
            print("提示: 本地分支落后于远程分支，请先执行 git pull 合并变更")
        return False


def main():
    parser = argparse.ArgumentParser(description="Git 自动推送脚本")
    parser.add_argument("--force", "-f", action="store_true", help="使用强制推送")
    parser.add_argument("--branch", "-b", default="main", help="指定分支名称")
    args = parser.parse_args()

    # 查找git仓库根目录
    git_root = find_git_root(os.path.dirname(os.path.abspath(__file__)))
    if not git_root:
        print("错误: 无法找到git仓库根目录")
        return

    # 切换到git仓库根目录
    os.chdir(git_root)
    print(f"已切换到git仓库根目录: {git_root}")

    # 检查远程仓库是否存在
    remotes = ["origin", "gitcode"]
    for remote in remotes.copy():
        if not get_remote_url(remote):
            print(f"警告: 远程仓库 {remote} 不存在，跳过")
            remotes.remove(remote)

    if not remotes:
        print("错误: 没有可用的远程仓库")
        return

    # 尝试对每个远程仓库先pull再push
    for remote in remotes:
        print(f"\n处理远程仓库: {remote} ({get_remote_url(remote)})")
        if git_pull(remote, args.branch):
            git_push(remote, args.branch, args.force)


if __name__ == "__main__":
    main()

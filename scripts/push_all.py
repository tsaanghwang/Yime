# scripts/push_all.py
import subprocess
import argparse


def git_pull(remote, branch="main"):
    try:
        print(f"正在从 {remote} 仓库拉取 {branch} 分支最新变更...")
        subprocess.run(["git", "pull", remote, branch], check=True)
        print(f"{remote} 拉取成功")
    except subprocess.CalledProcessError as e:
        print(f"{remote} 拉取失败: {e}")
        return False
    return True


def git_push(remote, branch="main", force=False):
    try:
        print(f"正在推送代码到 {remote} 仓库...")
        command = ["git", "push", remote, branch]
        if force:
            command.insert(2, "-f")
            print("警告: 使用强制推送(-f)，这将覆盖远程分支")
        subprocess.run(command, check=True)
        print(f"{remote} 推送成功")
    except subprocess.CalledProcessError as e:
        print(f"{remote} 推送失败: {e}")
        print("提示: 可能需要先解决合并冲突或手动执行 git pull")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Git 自动推送脚本")
    parser.add_argument("--force", "-f", action="store_true", help="使用强制推送")
    parser.add_argument("--branch", "-b", default="main", help="指定分支名称")
    args = parser.parse_args()

    if git_pull("origin", args.branch):
        git_push("origin", args.branch, args.force)
    git_push("gitcode", args.branch, args.force)

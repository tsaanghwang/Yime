# scripts/push_all.py
import subprocess


def git_pull(remote):
    try:
        print(f"正在从 {remote} 仓库拉取最新变更...")
        subprocess.run(["git", "pull", remote, "main"], check=True)
        print(f"{remote} 拉取成功")
    except subprocess.CalledProcessError as e:
        print(f"{remote} 拉取失败: {e}")
        return False
    return True


def git_push(remote):
    try:
        print(f"正在推送代码到 {remote} 仓库...")
        subprocess.run(["git", "push", remote, "main"], check=True)
        print(f"{remote} 推送成功")
    except subprocess.CalledProcessError as e:
        print(f"{remote} 推送失败: {e}")
        print("提示: 可能需要先解决合并冲突或手动执行 git pull")


if __name__ == "__main__":
    if git_pull("origin"):
        git_push("origin")
    git_push("gitcode")

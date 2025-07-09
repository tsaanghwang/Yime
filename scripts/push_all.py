# scripts/push_all.py
import subprocess


def git_push(remote):
    try:
        print(f"正在推送代码到 {remote} 仓库...")
        subprocess.run(["git", "push", remote, "main"], check=True)
        print(f"{remote} 推送成功")  # 新增成功提示
    except subprocess.CalledProcessError:
        print(f"{remote} 推送失败")


if __name__ == "__main__":
    git_push("origin")
    git_push("gitcode")

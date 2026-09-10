# PowerShell 统一预检与执行

入口：`python tools/powershell/run_checked.py`。默认 PS7；兼容性测试显式选择 `--edition ps5`。预检和执行在同一次目标 PowerShell 进程中完成，不调用模型，不加载用户 profile，不重试、不安装依赖。

```text
python tools/powershell/run_checked.py --script tools/yimecore/test-local13-maintenance-preparation.ps1 --edition ps5
python tools/powershell/run_checked.py --script tools/yimecore/test-local-startup-health.ps1 --params-file .tmp/health-params.json
python tools/powershell/run_checked.py --command "Get-Date" --check-only
```

参数文件示例：`{"OutputPath":".tmp/health-result.json"}`。相对路径按调用者工作目录解析；脚本自身的 `$PSScriptRoot` 语义保持。JSON 字符串经标准输入传递给执行器，不拼接为 PowerShell 代码。复杂命令先写入临时脚本，避免调用入口之前就发生 shell 引号错误。

预检检查目标 shell 是否存在、脚本路径和扩展名、目标版本的 AST 语法、无条件必填参数以及静态参数名。动态参数和参数集组合交给 PowerShell 原生绑定器；此工具不执行脚本来推测参数，也不检查被调用脚本的完整依赖。`--check-only` 不执行正文；普通模式预检成功后执行一次，保留输出和退出码。预检失败退出 2，正文异常退出 1，脚本显式退出码原样保留。

测试覆盖 PS5/PS7 的缺参、未知参数、缺失路径、语法错误、仅检查无副作用、带空格路径执行、显式失败退出码和字面量引号。运行 `python -m unittest discover -s tools/powershell -p test_run_checked.py -v`。

项目 `AGENTS.md` 要求后续 PowerShell 工作使用此入口。未配置或声称当前 Codex 客户端已具备全局每次调用的强制钩子；直接绕过入口的程序不会被拦截。安装维护上下文、控制器审核哈希及运行时回归仍由原有工具负责。本工具能减少调用失误，不能防止所有 PowerShell 或 CI 失败。

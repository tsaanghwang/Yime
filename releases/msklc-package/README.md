# MSKLC GUI Package Output

来源：`Microsoft Keyboard Layout Creator 1.4` 的 `Build DLL and Setup Package`。

生成时间：2026-04-08

内容：

- `setup.exe`
- `Yinyuan_amd64.msi`
- `Yinyuan_i386.msi`
- `Yinyuan_ia64.msi`
- `install-amd64-admin.cmd`
- `install-amd64-manual.cmd`
- `install-amd64-manual.ps1`
- `enable-yinyuan-for-current-user.cmd`
- `enable-yinyuan-for-current-user.ps1`
- `restore-default-chinese-keyboards.cmd`
- `restore-default-chinese-keyboards.ps1`
- `unregister-yinyuan-machine.cmd`
- `unregister-yinyuan-machine.ps1`
- `amd64/Yinyuan.dll`
- `i386/Yinyuan.dll`
- `ia64/Yinyuan.dll`
- `wow64/Yinyuan.dll`

说明：

- 这套产物来自 BMP PUA 投影版 `yinyuan.klc`。
- GUI verify 所需兼容修正已固化到 `tools/generate_klc_from_manual_layout.py`。
- `releases/msklc-amd64/Yinyuan.dll` 与 `releases/msklc-wow64/Yinyuan.dll` 已同步刷新为这次 GUI 打包输出对应版本。
- `install-amd64-admin.cmd` 仍用于优先尝试原生 MSI 安装。
- 如果本机持续出现 `MSI 2755 / unexpected error 110`，可改用 `install-amd64-manual.cmd` 直接复制 DLL 并注册键盘布局，绕过 Windows Installer。
- `install-amd64-manual.ps1` 现在只负责复制 DLL、注册 `HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layouts\Axxx0804`，并尝试 `LoadKeyboardLayoutW` 刷新当前会话。它不会再修改 `HKCU\Keyboard Layout\Preload` 或 `HKCU\Keyboard Layout\Substitutes`，避免把微软拼音、搜狗等中文输入法的底层键盘替换掉。
- `enable-yinyuan-for-current-user.cmd` 会把音元布局作为当前用户的单独键盘项加入 `HKCU\Keyboard Layout\Preload`，同时保留默认的 `00000804`，适合安全测试键位布局。
- `restore-default-chinese-keyboards.cmd` 会把当前用户恢复到只保留默认中文键盘 `00000804`，用于测试结束后一键回滚。
- `unregister-yinyuan-machine.cmd` 会移除 HKLM 下的 Yinyuan 键盘注册项和系统 DLL，用于 MSKLC 因名字或描述冲突而无法重新编译时的彻底清理。

如果提示安装成功，但任务栏里仍然没有输入法工具栏：

- 先注销并重新登录一次，让 Text Services Framework 重新加载自定义布局。
- 打开“设置 -> 时间和语言 -> 输入 -> 高级键盘设置”，确认没有把语言栏隐藏。
- 如果你只是想恢复微软拼音或搜狗的正常状态，确保 `HKCU\Keyboard Layout\Preload` 里只保留系统默认的 `00000804`，不要把音元布局写进去。
- 如果任务栏里仍然没有显示音元布局，通常是当前会话还没刷新；先注销并重新登录，再检查语言栏是否隐藏。

推荐测试流程：

- 先运行 `install-amd64-manual.cmd` 完成 DLL 和 HKLM 注册。
- 再运行 `enable-yinyuan-for-current-user.cmd`，把音元布局作为单独键盘项加入当前用户。
- 测试结束后运行 `restore-default-chinese-keyboards.cmd`，恢复到只保留系统默认中文键盘。

如果 MSKLC 重新编译时报下面这类错误：

- `ERROR: The keyboard name 'Yinyuan' is already in use on this machine.`
- `ERROR: The keyboard description 'Chinese (Simplified) - Yinyuan' is already in use on this machine.`

有两种处理方式：

- 运行 `unregister-yinyuan-machine.cmd`，彻底卸载当前机器上的 Yinyuan 注册，再重新编译。
- 或者在生成 KLC 时改一个临时测试名，例如：`tools/generate_klc_from_manual_layout.py --keyboard-name YinyuanTest --keyboard-description "Chinese (Simplified) - Yinyuan Test"`。

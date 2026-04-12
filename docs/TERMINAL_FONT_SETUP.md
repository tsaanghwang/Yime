# Windows Terminal 字体配置指南

## 问题说明
在交互窗口使用 "YinYuan Regular" 字体时，字符宽度有问题。
改用 "Noto Sans" 字体可以正常显示，包括私用区字符。

## 解决方案

### 方法1：通过Windows Terminal设置界面修改

1. 打开 Windows Terminal
2. 按 `Ctrl + ,` 打开设置
3. 选择 "默认值" 或特定的配置文件（如 PowerShell）
4. 点击 "外观"
5. 在 "字体" 下拉框中选择 "Noto Sans"
6. 点击 "保存"

### 方法2：直接修改配置文件

1. 打开 Windows Terminal
2. 按 `Ctrl + Shift + ,` 打开 settings.json
3. 在 defaults 或特定 profile 中添加：

```json
{
    "profiles": {
        "defaults": {
            "font": {
                "face": "Noto Sans",
                "size": 12
            }
        }
    }
}
```

或针对特定配置：

```json
{
    "profiles": {
        "list": [
            {
                "name": "PowerShell",
                "font": {
                    "face": "Noto Sans",
                    "size": 12
                }
            }
        ]
    }
}
```

### 方法3：PowerShell 配置文件

在 PowerShell 配置文件中设置：

```powershell
# 打开配置文件
notepad $PROFILE

# 添加以下内容
$Host.UI.RawUI.FontName = "Noto Sans"
```

### 方法4：CMD 窗口

1. 打开 CMD
2. 右键标题栏 → 属性
3. 选择 "字体" 选项卡
4. 选择 "Noto Sans"
5. 点击 "确定"

## Noto Sans 字体说明

### 优点
- ✅ 支持私用区字符（PUA）
- ✅ 字符宽度正确
- ✅ 显示清晰
- ✅ 开源免费

### 包含的私用区字符
- U+E000-U+F8FF: 基本多文种平面私用区
- 音元系统使用的特殊字符

## 验证字体是否可用

### PowerShell
```powershell
# 列出所有可用字体
[System.Drawing.FontFamily]::Families | Where-Object { $_.Name -like "*Noto*" } | Select-Object Name
```

### Python
```python
import tkinter as tk
root = tk.Tk()
fonts = tk.font.families()
print("Noto Sans available:", "Noto Sans" in fonts)
root.destroy()
```

## 如果 Noto Sans 不可用

### 安装 Noto Sans 字体

1. 访问 Google Fonts: https://fonts.google.com/noto
2. 下载 Noto Sans 字体
3. 解压后右键字体文件 → 安装
4. 重启终端

或使用 PowerShell 安装：

```powershell
# 下载并安装 Noto Sans
$fontUrl = "https://fonts.google.com/download?family=Noto%20Sans"
$fontFile = "$env:TEMP\NotoSans.zip"
Invoke-WebRequest -Uri $fontUrl -OutFile $fontFile
Expand-Archive -Path $fontFile -DestinationPath "$env:TEMP\NotoSans"
Get-ChildItem "$env:TEMP\NotoSans\*.ttf" | ForEach-Object {
    $font = $_.FullName
    $shell = New-Object -ComObject Shell.Application
    $fontsFolder = $shell.Namespace(0x14)
    $fontsFolder.CopyHere($font)
}
```

## 测试私用区字符显示

```python
# 测试私用区字符
test_chars = [
    "\uE000",  # 私用区起始字符
    "\uE4F1",  # 音元字符示例
    "\uE4E9",  # 音元字符示例
]

for char in test_chars:
    print(f"字符: {char}, Unicode: U+{ord(char):04X}")
```

## 注意事项

1. **修改后需要重启终端**
2. **某些终端可能不支持私用区字符**
3. **Windows Terminal 支持最好**
4. **旧版 CMD 可能有限制**

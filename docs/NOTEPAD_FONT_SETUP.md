# 记事本字体设置指南

## 问题说明
记事本默认不支持设置字体，但可以通过以下方法解决：

## 方法1：使用Windows Terminal + Vim/Notepad++

**推荐使用支持字体设置的编辑器**：
- Windows Terminal + Vim
- Notepad++
- VS Code
- Sublime Text

---

## 方法2：修改记事本默认字体（Windows 10/11）

### Windows 11
1. 打开记事本
2. 点击 "格式" → "字体"
3. 选择 "Noto Sans"
4. 点击 "确定"

### Windows 10
记事本不支持自定义字体，建议使用其他编辑器

---

## 方法3：使用注册表修改记事本字体

**注意**：此方法可能不适用于所有Windows版本

```powershell
# 设置记事本字体
$fontKey = "HKCU:\Software\Microsoft\Notepad"

Set-ItemProperty -Path $fontKey -Name "lfFaceName" -Value "Noto Sans" -Type String -Force
Set-ItemProperty -Path $fontKey -Name "lfHeight" -Value "-12" -Type DWord -Force
Set-ItemProperty -Path $fontKey -Name "lfWeight" -Value "400" -Type DWord -Force
```

---

## 方法4：使用Notepad++（推荐）

### 安装Notepad++
1. 下载：https://notepad-plus-plus.org/downloads/
2. 安装

### 设置字体
1. 打开Notepad++
2. 设置 → 首选项
3. 选择 "字体" 选项卡
4. 字体名称：选择 "Noto Sans"
5. 字体大小：12
6. 点击 "关闭"

### 优点
- ✅ 完全支持自定义字体
- ✅ 支持私用区字符
- ✅ 功能强大
- ✅ 免费开源

---

## 方法5：使用VS Code

### 设置字体
1. 打开VS Code
2. Ctrl + , 打开设置
3. 搜索 "font family"
4. 输入：`'Noto Sans', Consolas, 'Courier New', monospace`
5. 保存

### 或在settings.json中添加
```json
{
    "editor.fontFamily": "'Noto Sans', Consolas, 'Courier New', monospace",
    "editor.fontSize": 12
}
```

---

## 方法6：使用Windows Terminal测试

**最简单的方法**：直接在Windows Terminal中测试

```bash
# 测试私用区字符
python -c "print('\uE4F1 \uE4E9 \uE4EA')"
```

**Windows Terminal已配置Noto Sans字体，可以直接显示私用区字符**

---

## 推荐编辑器对比

| 编辑器 | 字体设置 | 私用区字符 | 推荐度 |
|--------|---------|-----------|--------|
| **Windows Terminal** | ✅ 支持 | ✅ 显示 | ⭐⭐⭐⭐⭐ |
| **Notepad++** | ✅ 支持 | ✅ 显示 | ⭐⭐⭐⭐⭐ |
| **VS Code** | ✅ 支持 | ✅ 显示 | ⭐⭐⭐⭐⭐ |
| **Word** | ✅ 支持 | ✅ 显示 | ⭐⭐⭐⭐☆ |
| **记事本 (Win11)** | ✅ 支持 | ⚠️ 可能 | ⭐⭐⭐☆☆ |
| **记事本 (Win10)** | ❌ 不支持 | ❌ 不显示 | ⭐☆☆☆☆ |

---

## 测试私用区字符

### Python测试
```python
# 测试音元字符
chars = ['\uE4F1', '\uE4E9', '\uE4EA', '\uE4EB']
for char in chars:
    print(f"字符: {char}, Unicode: U+{ord(char):04X}")
```

### PowerShell测试
```powershell
# 测试私用区字符
[char]0xE4F1
[char]0xE4E9
[char]0xE4EA
```

---

## 当前状态

✅ **Word** - 可以输入和显示私用区字符
✅ **Windows Terminal** - 已配置Noto Sans，可以显示
⚠️ **记事本** - 可能需要额外设置或使用其他编辑器

---

## 建议

**最佳实践**：
1. **开发测试**：使用Windows Terminal
2. **文档编辑**：使用Word或Notepad++
3. **代码编辑**：使用VS Code

**避免使用**：
- Windows 10 记事本（不支持自定义字体）
- 旧版CMD（字体支持有限）

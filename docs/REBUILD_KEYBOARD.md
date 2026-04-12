# 键盘布局重新编译指南

## 问题说明

键盘布局在测试过程中被改变了，需要重新生成并编译。

---

## 步骤1：重新生成布局文件

**已完成**：
```bash
python tools/generate_klc_from_manual_layout.py
```

**结果**：
```
Updated yinyuan.klc from internal_data\manual_key_layout.json
```

---

## 步骤2：重新编译DLL和安装包

### 方法1：使用MSKLC GUI（推荐）

**步骤**：

1. **打开MSKLC**
   ```
   "C:\Program Files (x86)\Microsoft Keyboard Layout Creator 1.4\MSKLC.exe"
   ```

2. **加载布局文件**
   - File → Load Source File
   - 选择 `yinyuan.klc`
   - 确认布局正确

3. **验证布局**
   - 检查每个键的映射
   - 确认私用区字符正确
   - 确认与manual_key_layout.json一致

4. **生成安装包**
   - Project → Build DLL and Setup Package
   - 选择输出目录
   - 等待编译完成

5. **检查输出**
   - setup.exe
   - Yinyuan_amd64.msi
   - Yinyuan.dll
   - 其他文件

---

### 方法2：使用命令行脚本

**运行编译脚本**：
```bash
python tools/run_msklc_packaging_pipeline.py --open-msklc always
```

**说明**：
- 会自动打开MSKLC
- 需要手动完成GUI步骤
- 自动复制输出文件

---

## 步骤3：卸载旧键盘

**重要**：必须先卸载旧键盘

### 方法1：使用卸载程序

**位置**：
```
releases\msklc-package\setup.exe
```

**步骤**：
1. 运行 `setup.exe`
2. 选择 "Remove"
3. 完成
4. 注销并重新登录

---

### 方法2：手动卸载

**步骤**：
1. 设置 → 时间和语言 → 语言
2. 找到 "中文（简体）"
3. 点击 "选项"
4. 找到 "Yinyuan"
5. 点击 "删除"
6. 注销并重新登录

---

### 方法3：使用注册表

**删除注册表项**：
```powershell
# 删除预加载
Remove-ItemProperty -Path "HKCU:\Keyboard Layout\Preload" -Name "*" -ErrorAction SilentlyContinue

# 删除替换
Remove-ItemProperty -Path "HKCU:\Keyboard Layout\Substitutes" -Name "A0000804" -ErrorAction SilentlyContinue

# 注销并重新登录
```

---

## 步骤4：安装新键盘

### 方法1：使用安装程序

**步骤**：
1. 运行 `releases\msklc-package\setup.exe`
2. 选择 "Install"
3. 完成
4. 注销并重新登录

---

### 方法2：手动安装

**步骤**：
1. 复制DLL到系统目录
2. 注册键盘布局
3. 添加到用户配置
4. 注销并重新登录

---

## 步骤5：验证安装

### 检查键盘布局

**方法1：设置界面**
1. 设置 → 时间和语言 → 语言
2. 找到 "中文（简体）"
3. 点击 "选项"
4. 确认 "Yinyuan" 存在

---

**方法2：注册表**
```powershell
# 检查系统安装
Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layouts" |
    Where-Object { $_.PSChildName -eq "A0000804" }

# 检查用户激活
Get-ItemProperty "HKCU:\Keyboard Layout\Preload"
```

---

**方法3：输入法切换**
1. Win + Space
2. 查看是否有 "Chinese (Simplified) - Yinyuan"
3. 选择并测试

---

## 步骤6：测试键盘

### 测试步骤

1. **打开记事本**
2. **切换到音元键盘**（Win + Space）
3. **敲击键盘**
4. **观察输出**

### 预期结果

**根据manual_key_layout.json**：

| 键 | Base | Shift |
|----|------|-------|
| ` | N22 | ~ |
| 1 | N09 | ! |
| 2 | N01 | N05 |
| 3 | N02 | N06 |
| 4 | N03 | N07 |
| 5 | N04 | N08 |
| q | N10 | N15 |
| w | w | N16 |
| e | M18 | N17 |
| r | M17 | N18 |
| ... | ... | ... |

**N01-N24**：噪音符号
**M01-M33**：音乐符号

---

## 完整流程

### 一键执行（推荐）

```bash
# 1. 重新生成布局
python tools/generate_klc_from_manual_layout.py

# 2. 打开MSKLC编译
python tools/run_msklc_packaging_pipeline.py --open-msklc always

# 3. 在MSKLC中：
#    - File → Load Source File → yinyuan.klc
#    - Project → Build DLL and Setup Package
#    - 选择输出目录
#    - 等待完成

# 4. 卸载旧键盘
#    - 运行旧setup.exe → Remove
#    - 或手动删除

# 5. 注销并重新登录

# 6. 安装新键盘
#    - 运行新setup.exe → Install

# 7. 注销并重新登录

# 8. 测试
#    - Win + Space → 选择Yinyuan
#    - 在记事本中测试
```

---

## 注意事项

### 重要提醒

1. **必须卸载旧键盘**
   - 否则可能冲突
   - 可能使用旧布局

2. **必须注销并重新登录**
   - 键盘布局是会话级别
   - 注册表更改需要重新加载

3. **验证布局正确**
   - 检查manual_key_layout.json
   - 检查生成的yinyuan.klc
   - 测试每个键

4. **备份旧版本**
   - 备份旧的安装包
   - 以防需要回滚

---

## 故障排除

### 问题1：MSKLC无法打开

**解决**：
- 确认MSKLC已安装
- 路径：`C:\Program Files (x86)\Microsoft Keyboard Layout Creator 1.4\MSKLC.exe`

---

### 问题2：编译失败

**解决**：
- 检查yinyuan.klc格式
- 检查私用区字符
- 查看MSKLC错误信息

---

### 问题3：安装失败

**解决**：
- 先卸载旧版本
- 注销并重新登录
- 以管理员权限运行

---

### 问题4：布局不正确

**解决**：
- 检查manual_key_layout.json
- 重新生成yinyuan.klc
- 重新编译安装

---

## 总结

**关键步骤**：
1. ✅ 重新生成布局文件
2. ⏳ 重新编译DLL和安装包
3. ⏳ 卸载旧键盘
4. ⏳ 注销并重新登录
5. ⏳ 安装新键盘
6. ⏳ 注销并重新登录
7. ⏳ 测试验证

**下一步**：
运行MSKLC编译安装包

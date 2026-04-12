# 键盘布局生成完整流程

## 设计约束

在阅读本流程前，请先阅读 [码点与中间层策略](CODEPOINT_POLICY.md)。

键盘布局流程依赖以下前提：

1. `N01-N24` 与 `M01-M33` 是语义槽位层，不是可删的临时中间文件。
2. `manual_key_layout.json` 负责键位到语义槽位的映射，不负责决定长期 canonical 码点。
3. `BMP PUA` 更适合作为当前 Windows 工具链的投影层，不应自动取代长期规范字符层。

如果某次测试或重构需要绕过这些前提，应该先审查生成链和投影层，而不是直接改数据库或删除中间层。

## 流程概述

键盘布局的生成不是从`manual_key_layout.json`开始的，而是一个完整的流程：

```
拼音解码 → 私用区字符分配 → 布局合理性分析 → manual_key_layout.json → yinyuan.klc → DLL/安装包
```

---

## 完整流程步骤

### 步骤1：拼音解码

**目的**：分析拼音结构和音元分布

**相关文件**：
- `syllable/` - 拼音分析
- `yime_theory/` - 音元理论

**输出**：
- 音元列表
- 频率统计
- 组合规则

---

### 步骤2：私用区字符分配

**目的**：为每个音元分配私用区字符（PUA）

**相关文件**：
- `internal_data/bmp_pua_trial_projection.json` - PUA映射

**输出**：
- N01-N24 → 噪音符号 → E4F1-E508
- M01-M33 → 音乐符号 → E509-E529

**说明**：
- 私用区范围：U+E000-U+F8FF
- 需要考虑字体支持
- 需要避免冲突

---

### 步骤3：布局合理性分析

**目的**：分析键盘布局的合理性

**考虑因素**：
- 高频音元放在容易按的位置
- 左右手平衡
- 手指移动距离
- 组合便利性

**相关文件**：
- `tools/check_layout_runtime_consistency.py` - 一致性检查
- `tools/resolve_manual_key_layout.py` - 布局解析

**输出**：
- 布局评估报告
- 优化建议

---

### 步骤4：生成manual_key_layout.json

**目的**：生成最终的键盘布局定义

**相关文件**：
- `internal_data/manual_key_layout.json` - 布局定义
- `internal_data/key_to_symbol.json` - 符号映射

**内容**：
- 每个键的映射
- Base/Shift/AltGr层
- 符号或字面字符

---

### 步骤5：生成yinyuan.klc

**目的**：生成MSKLC源文件

**工具**：
```bash
python tools/generate_klc_from_manual_layout.py
```

**输入**：
- `manual_key_layout.json`
- `key_to_symbol.json`
- `bmp_pua_trial_projection.json`

**输出**：
- `yinyuan.klc` - MSKLC源文件

---

### 步骤6：编译DLL和安装包

**目的**：生成可安装的键盘布局

**工具**：
- MSKLC (Microsoft Keyboard Layout Creator)
- 或 `tools/run_msklc_packaging_pipeline.py`

**输出**：
- `Yinyuan.dll` - 键盘DLL
- `setup.exe` - 安装程序
- `Yinyuan_amd64.msi` - 64位安装包
- `Yinyuan_i386.msi` - 32位安装包

---

## 流程图

```
┌─────────────────┐
│  拼音解码分析   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 私用区字符分配  │
│  N01-N24 (噪音) │
│  M01-M33 (音乐) │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 布局合理性分析  │
│  - 高频优先     │
│  - 左右平衡     │
│  - 移动距离     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│manual_key_layout│
│     .json       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  yinyuan.klc    │
│  (MSKLC源文件)  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  MSKLC编译      │
│  - DLL          │
│  - 安装包       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  安装到系统     │
└─────────────────┘
```

---

## 当前状态

### 已完成的部分

根据您的说明，以下部分可能不需要修改：

1. ✅ **拼音解码分析** - 已完成
2. ✅ **私用区字符分配** - 已完成
3. ✅ **布局合理性分析** - 已完成
4. ✅ **manual_key_layout.json** - 已定义

### 需要重新执行的部分

1. ⏳ **生成yinyuan.klc** - 已重新生成
2. ⏳ **编译DLL和安装包** - 需要执行
3. ⏳ **安装到系统** - 需要执行

---

## 为什么布局会被改变

### 可能的原因

1. **测试过程中修改了manual_key_layout.json**
   - 手动编辑
   - 或程序修改

2. **使用了错误的生成流程**
   - 跳过了某些步骤
   - 或使用了旧版本

3. **安装包使用了旧布局**
   - 没有重新编译
   - 或使用了缓存的版本

---

## 解决方案

### 方案1：重新执行完整流程

**如果前面的步骤需要修改**：

```bash
# 1. 拼音解码（如果需要）
# ...

# 2. 私用区字符分配（如果需要）
# ...

# 3. 布局合理性分析（如果需要）
python tools/check_layout_runtime_consistency.py
python tools/resolve_manual_key_layout.py

# 4. 生成manual_key_layout.json（如果需要）
# ...

# 5. 生成yinyuan.klc
python tools/generate_klc_from_manual_layout.py

# 6. 编译安装包
python tools/run_msklc_packaging_pipeline.py --open-msklc always
```

---

### 方案2：只重新编译（推荐）

**如果前面的步骤不需要修改**：

```bash
# 1. 重新生成yinyuan.klc（已完成）
python tools/generate_klc_from_manual_layout.py

# 2. 编译安装包
python tools/run_msklc_packaging_pipeline.py --open-msklc always

# 3. 卸载旧键盘
# 4. 注销并重新登录
# 5. 安装新键盘
# 6. 注销并重新登录
# 7. 测试
```

---

## 验证布局正确性

### 检查manual_key_layout.json

**确认以下内容**：

1. **版本信息**
   ```json
   "version": "2026-04-10",
   "layout_status": "final_candidate_v1"
   ```

2. **符号映射**
   - N01-N24：噪音符号
   - M01-M33：音乐符号

3. **键位分配**
   - 高频音元在容易按的位置
   - 左右手平衡
   - 符合人体工程学

---

### 检查yinyuan.klc

**确认以下内容**：

1. **头部信息**
   ```
   KBD	Yinyuan	"Chinese (Simplified) - Yinyuan"
   LOCALEID	"00000804"
   ```

2. **布局映射**
   - 每个键的Base/Shift/AltGr
   - 私用区字符正确
   - 与manual_key_layout.json一致

---

### 测试键盘

**测试步骤**：

1. 安装新键盘
2. Win + Space切换
3. 在记事本中测试每个键
4. 对比manual_key_layout.json
5. 确认输出正确

---

## 总结

### 完整流程

```
拼音解码 → PUA分配 → 布局分析 → manual_key_layout.json → yinyuan.klc → DLL/安装包
```

### 当前状态

- ✅ 前面的步骤已完成（不需要修改）
- ✅ yinyuan.klc已重新生成
- ⏳ 需要重新编译安装包
- ⏳ 需要重新安装

### 下一步

**重新编译安装包**：
```bash
python tools/run_msklc_packaging_pipeline.py --open-msklc always
```

**然后**：
1. 卸载旧键盘
2. 注销并重新登录
3. 安装新键盘
4. 注销并重新登录
5. 测试验证

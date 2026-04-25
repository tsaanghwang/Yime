# MSKLC Precompile Checklist

在把 [yinyuan.klc](/c:/dev/Yime/yinyuan.klc) 丢进 MSKLC 之前，先跑下面这套检查，能挡掉大多数结构性错误。

补充说明：`internal_data/manual_key_layout.json` 里的 `manual` 是历史文件名，当前表示布局真源，不表示 manual install 或手工编译链路。

1. 源布局先过一致性检查。

```powershell
python tools/check_layout_runtime_consistency.py --layout internal_data/manual_key_layout.json --symbols internal_data/key_to_symbol.json --resolved-layout internal_data/manual_key_layout.resolved.json --json-output internal_data/layout_runtime_consistency_report.json
```

要求：状态不是 `error`，并且没有 `Duplicate symbol_key assignment`、`Duplicate physical slot`。

1. 用官方流水线重生产物，不要手改最终 [yinyuan.klc](/c:/dev/Yime/yinyuan.klc)。

```powershell
python tools/run_layout_pipeline.py --open-msklc never --export-visual-table
```

要求：四步都完成，生成 [internal_data/manual_key_layout.resolved.json](/c:/dev/Yime/internal_data/manual_key_layout.resolved.json)、[internal_data/klc_layout_visual_table.md](/c:/dev/Yime/internal_data/klc_layout_visual_table.md)、[yinyuan.klc](/c:/dev/Yime/yinyuan.klc)。

1. 检查 KLC 文本结构。

要求：

- 文件编码是 `UTF-16 LE`。
- `LAYOUT`、`KEYNAME`、`KEYNAME_EXT`、`DESCRIPTIONS`、`LANGUAGENAMES`、`ENDKBD` 段都在。
- 空行节奏和基线一致，不要出现大段连续空行。
- 不要手工在记录行之间插额外换行。

1. 检查当前方案的关键位没有被回退。

当前定版应满足：

- `M05 -> G`
- `N06 -> OEM_PERIOD`
- `N09 -> OEM_6`
- `N10 -> OEM_7`
- `N11 -> N`
- `M07 -> OEM_2`
- `AltGr+Y -> N23`
- `AltGr+U -> N24`
- `AltGr+P/[ /]` 留空

1. 检查稀疏 AltGr 是否仍然稀疏。

要求：只保留明确选中的低频位；不要让中文标点或调试残留重新混回 `AltGr`。

1. 再做一次 Problems 面板检查。

至少确认：

- [internal_data/manual_key_layout.json](/c:/dev/Yime/internal_data/manual_key_layout.json) 无 JSON 错误。
- [yinyuan.klc](/c:/dev/Yime/yinyuan.klc) 无明显文本损坏。

1. 最后再打开 MSKLC。

```powershell
& 'C:\Program Files (x86)\Microsoft Keyboard Layout Creator 1.4\MSKLC.exe' 'C:\dev\Yime\yinyuan.klc'
```

如果 MSKLC 报解析错误，优先回查：

- 是否手改过 [yinyuan.klc](/c:/dev/Yime/yinyuan.klc) 的空行或编码
- 是否把候选 `.klc` 直接复制成官方产物而没走流水线
- 是否在源布局里留下了重复 `symbol_key`

# KLE 触摸模板工作流

[Keyboard Layout Editor](https://www.keyboard-layout-editor.com/#/) 只用于编辑触摸键面的几何与外观。仓库保存 KLE 下载得到的严格 JSON；不要把网页“Raw data”标签中省略引号和顶层方括号的宽松文本直接提交。

当前模板：`design/touch-terminal-60.kle.json`。

## 数据所有权

- KLE 模板拥有触摸键的位置、宽高、间距、顺序、颜色及图例。
- 每个键必须包含且只包含一个精确的稳定 ID：`N01`–`N27` 或 `M01`–`M33`。ID 可位于任意 legend 槽；其他 legend 仅供设计预览。
- `internal_data/manual_key_layout.json` 继续独占音元 ID 到桌面物理键/ASCII 的投影以及受控共享组。KLE 不得定义或覆盖这些键码。
- `data/layout.json` 是两类资料合并后的生成物，不能手工编辑。

## 从 KLE 导入

1. 在 KLE 打开模板 JSON，调整键的位置、矩形宽高、间距、颜色和 legend。
2. 使用 KLE 的 **Download JSON**，不要复制宽松 Raw data。
3. 在仓库外或 `.tmp/` 中先验证下载文件：

   ```text
   python -X utf8 prototypes/touch-terminal/kle_layout.py <下载的布局.json>
   ```

4. 验证通过并人工查看差异后，用下载文件更新 `design/touch-terminal-60.kle.json`，再重新生成与验证：

   ```text
   python -X utf8 prototypes/touch-terminal/generate_data.py
   python -X utf8 prototypes/touch-terminal/validate.py
   ```

支持 KLE 的行、`x/y` 偏移、矩形 `w/h`、颜色及 legend。首轮实屏基线有意拒绝旋转、异形双矩形、decal、stepped 与 homing 属性，因为当前触摸渲染器不能忠实保留这些形状。键不得重叠、使用负坐标、缺失、重复或加入未知音元 ID。

几何/外观模型变化只改变 `touchTemplateId`；纯 JSON 缩进或换行变化只改变来源 SHA-256。桌面投影变化才改变 `layoutId`。实屏记录同时保存这些身份，避免把同一桌面编码下的不同触摸模板混为一组数据。

# 当前语言键：CN/EN单一显示修复

用户在P10四项功能正常后报告：固定CN EN双标签难以辨认当前语言，导致误按。原话与旧包功能结果见[原反馈](../p01-p10/user-reports/p10-finger-en-tab-esc-modes-and-label-issue.json)。显示问题独立于切换功能是否正常，不把原显示问题改成已通过。

## 修改与验证

在共享预览/宿主绘制路径中，仅为语言切换键R01K03覆盖当前视图的显示标签：中文输入为CN，英文输入为EN；依据输入语言，不依据Layout键帽偏好。英文切原盘面仍显示EN。动作、键ID、几何、颜色、编码与隔离词典均未改，未编辑生成盘面文件。预览/宿主帮助和指南已同步说明。

相关Go测试、完整独立包三模式/资源拒绝/仓库外路径/渲染检查通过。开发者已用鼠标观察CN→EN→英文原盘面仍EN→CN四个实际窗口状态，见[视觉记录](visual-check.json)；该观察不代替真人手指或笔验收。宿主使用相同绘制代码，本次没有新增真实宿主输入测试。

## 新包和复测入口

本地新包：touch-language-label-20261026-amd64，exe SHA-256为73c729b2948a37bc461c7cbcc7c3e1277424f9f5874b6d0285b241a02b1b6865；[身份](package-identity.json)与[完整包检查](package-check.json)。基于PR #79合并提交9adc3cdd9634e0258b58c9a8945b3497fc8777ad的sourceChanges:true源码构建，未发布新CI包。

[预览入口](</C:/dev/Yime/.generated/touch-validation-20261025-x64-16inch/Start Language Label Preview.cmd>)；[宿主入口](</C:/dev/Yime/.generated/touch-validation-20261025-x64-16inch/Start Language Label Keyboard.cmd>)。两者包外独立保留，均使用58.8参数；预览不向宿主发送文本，不启用额外跟踪。开发观察窗口完成检查后已正常Close；请从新版入口重新启动，默认英文键帽偏好恢复为新进程初始值。旧包未覆盖。

真人定向复测待反馈：用手指点语言键，观察CN→EN→CN只出现当前状态一个标签；英文时点Layout切原盘面，语言键应仍EN，返回EN键帽后也仍EN。再各输入一组既有英文/中文夹具，确认切换与输出正常。先完成显示反馈，再继续P10余项。

## 结果归属

P10此前手指EN80个键两层共160项功能反馈属于旧包22e76c1b…；其中语言键固定双标签的显示问题单独保留。新包只有上述开发验证，未继承旧包整套物理通过。P01尺寸与屏幕平放记录继续保留，参考尺约97mm不改写成精确100mm。

## 真人定向复测完成

用户按前述手指CN→EN→CN与英文Layout切换两项回复“已测。正常。”，见[原反馈](physical-retest-user-result.json)。该语言键显示问题按请求范围关闭，未增加整套新包通过结论。后续逐键继续新包，既有160项保留旧包身份，逐层记录包哈希，见[P01/P10接续](../p01-p10/RESULT.zh-CN.md)。

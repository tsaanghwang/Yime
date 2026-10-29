# 键面字号与下档裁切修复

2026-10-27。用户反馈：“颜色暂时不深究。键面字符字号太小。下档太偏下，有一半没有露出来。”颜色保持灰色试用主题，不因此记为颜色验收通过。

旧绘制把每个字符限制在固定20px高的文字框，下档文字框从键底向上仅23px开始。私有音元字体实际行高超过该框；字形即使加载正确也会被裁掉。原ASCII15px、音元19px没有随本轮校准后的大键面调整。

新增GDI回归以同字体完整字形的笔画像素数作对照：旧路径在19px时M12只保留26/36个墨点，在36px时甚至为0/92；三个真实音元、两种字号均复现裁切。修复后六例保留完整笔画且不越出键面，详见[问题与回归](ISSUE_AND_FIX.json)。

现在按校准后1u像素尺寸计算键面字体：ASCII为20%、音元为23%，本屏58.8参数下分别31px和36px，约为原来两倍。顶部界面字体独立保留。文字位置使用所选字体的实际行高，上、中、下分别在键面内部定位；下档从键底留出边距，不再套20px裁切框。未更换字体文件、字形、编码、键位、命中区域、几何或词典，18u与原58.8参数保持。

本地x64包`.generated/touch-legend-readability-20261027-amd64`，exe SHA-256为`161df413c9f6ae6cf4aad43e575ad55f00c227f105f187a74d6b70a1d5759469`；源码基线9adc3cdd9634e0258b58c9a8945b3497fc8777ad，`sourceChanges:true`，不是CI包。见[完整身份](package-identity.json)。相对灰色试用版，载荷变化仅exe、指南和记录指南哈希的resources.json；布局、profile、字体和三模式隔离词典一致。

相关Go回归通过，完整包移出仓库/空工作目录三模式、资源拒绝检查通过，见[包检查](package-check.json)。开发者检查了[深色CN渲染图](dark-glyphs.png)：字号放大，下档字形完整，长功能键文字可见。渲染仍为2830×1442；这些属于开发证据，不能替代用户屏幕试用。另一张original-view-preference图仍是CN初始状态，不能称为EN视图结果。

关闭旧预览后打开[字号修正版预览](</C:/dev/Yime/.generated/touch-validation-20261025-x64-16inch/Start Larger Legends Preview.cmd>)。先核对上下档字符和音元是否完整、没有互相遮挡、字号是否合适；需要时用“字形→ID”检查ID文字，再恢复字形。当前先处理显示，勿把观察可读性直接填为新包输入通过。

[同版原配色预览](</C:/dev/Yime/.generated/touch-validation-20261025-x64-16inch/Start Larger Legends Original Colors Preview.cmd>)和[字号修正版宿主入口](</C:/dev/Yime/.generated/touch-validation-20261025-x64-16inch/Start Larger Legends Keyboard.cmd>)另备，不因此新增宿主验收。旧包与250项P10记录保留原身份；剩余CN150项、两支笔各400项仍待，见[测试记录](../../2026-10-26/p01-p10/RESULT.zh-CN.md)。

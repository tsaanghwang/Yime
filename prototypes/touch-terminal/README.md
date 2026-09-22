# Yime 音元触摸终端原型

**没有实体终端也能做。** 本目录提供一个完全在浏览器内运行的交互原型：60 个稳定音元 ID 各有独立按键，支持组合预览、退格、清空、候选选择/翻页、明确确认、尺寸试算和点按记录。鼠标、键盘、浏览器模拟触摸都能验证软件行为；真实手指误触率、输入速度和触控端到端延迟留待指定设备验证。

影响范围：**共享源数据 / 隔离原型**。没有修改 Go、Broker、TSF、安装器或规范布局；没有连接已安装输入法、命名管道、用户词库或学习库。确认只写到当前页面内存，刷新会重置全部预览和记录。本目录不进入输入法安装包。

## 本地运行

在仓库根目录执行（已有 Python 即可，无 npm 安装或前端构建）：

```text
python -X utf8 prototypes/touch-terminal/serve.py
```

打开 [本地原型](http://127.0.0.1:8765)。端口占用时可加 `--port 8766`；按 Ctrl+C 关闭。服务只监听 `127.0.0.1`、只提供本目录静态文件，不提供写入 API、目录浏览或仓库根目录访问。直接双击 HTML 不适用，因为浏览器需要通过 HTTP 加载模块和数据。加载后输入处理不访问网络。

建议首先按页面引导点 `N08 → M03 → M03 → M03`，得到“你”的固定候选；点候选只是高亮，再点“确认”。右侧“载入”可直接重放三组有来源的音元序列；“是”的样例含 13 个候选，可试第二页。

- 60 键按 N01–N27、M01–M33 排列为 10×6，是展示顺序，不是新物理键盘编码。键面使用已有教学标签、音元 ID 和原物理键提示，不要求安装私有字体。
- 同一键内抬起才输入；拖出再返回、系统取消、失焦均不输入未完成触摸。窄窗口支持在键区横向滑动，仍保留完整 60 键。
- 点击键盘/载入样例后，原物理键也可输入。裸数字始终组合；`Shift+1`…`Shift+9` 选择候选，`Enter` 明确确认，`Backspace` 退格，`Escape` 清空，`PageUp/Down` 翻页。Tab 焦点落在单个音元键时，Space/Enter 使用普通按钮激活语义。
- N12/N26、N25/N27 共享现有物理投影，但独立触摸 ID 不合并。物理键快捷输入采用主 ID N12/N25并提示；要表达另一个 ID，应点击独立触摸键。
- 候选只覆盖三个规范全码样例，不是完整输入引擎。任意组合可以预览；没有样例候选时确认禁用，不自动提交编码。没有改变三种输入模式、语流别名或候选分页所有权。
- 点按检查是固定 20 目标的软件冒烟流程；导出 JSON 标记实际 `pointerType`、命中/错键/取消、尺寸假设和前端计时。记录只在内存，用户点“导出”才下载；不是学习数据。事件记录保留最近 100 条、触摸与计时各最近 1000 条。会话达到协议上限后刷新重新开始。

## 数据如何追溯

`generate_data.py` 复用仓库现有布局解析/校验链：

1. 唯一可编辑键位源 `internal_data/manual_key_layout.json` → 已有受控共享映射 → 核对已生成的 `yime_yinyuan_layout.json`。
2. 标签和分组来自现有 `trainer/yinyuan_catalog.json`、`yinyuan_groups.json`；符号来自 `key_to_symbol.json`。60 ID 对应 58 个大小写敏感投影，布局身份复用仓库的投影摘要。
3. 样例四音元 ID 来自 `internal_data/yime_syllable_decomposition.tsv` 的规范分解，再投影为全码；候选另以 `hanzi_pinyin/pinyin.txt` 和 `yime_full.dict.yaml` 核对。绝不从词典键码反推音元，也不手填音元编码来修复词典。

两个生成 JSON 内含来源相对路径、SHA-256，样例还含来源行号。文本摘要统一使用 **UTF-8、LF、无 BOM**（`hashMode=utf8-lf-no-bom`），可跨 CRLF/LF checkout 重现。源数据变化后执行下列命令重新生成；生成数据不是第二份可编辑布局源：

```text
python -X utf8 prototypes/touch-terminal/generate_data.py
python -X utf8 prototypes/touch-terminal/generate_data.py --check
```

## 可重复验证

仓库 Python 3.14、Node.js 24 已验证；运行以下一条命令可执行不依赖浏览器的本地检查：

```text
python -X utf8 prototypes/touch-terminal/validate.py
```

涵盖源摘要/生成漂移、60 ID 和共享键、非法投影拒绝、样例来源、严格事件/幂等/陈旧候选、确认边界、会话上限、几何模型、静态服务目录隔离与 JS 语法。独立 CI 工作流 `touch-terminal.yml` 重复同一入口，不运行安装或宿主测试。

浏览器复验使用 Playwright CLI 0.1.21。先启动上述服务器，在仓库根目录执行；首次 npx 会下载测试工具，需要网络及本机 Chrome。运行页面本身不需要这些依赖：

```text
npx --yes --package @playwright/cli@0.1.21 playwright-cli -s=yime-touch open http://127.0.0.1:8765 --headed
npx --yes --package @playwright/cli@0.1.21 playwright-cli -s=yime-touch run-code --filename=prototypes/touch-terminal/browser-smoke.js
npx --yes --package @playwright/cli@0.1.21 playwright-cli -s=yime-touch close
```

脚本逐个检查 60 键，验证数字/Shift候选、拖出取消、确认/退格、13 候选翻页、焦点返回、20 次点按、JSON 导出，并在浏览器模拟触摸模式下验证 tap、`touchCancel` 和 390px 窗口横滚。截图和导出写入忽略目录 `output/playwright/`；CLI 临时状态位于 `.playwright-cli/`。这些窄视口是浏览器响应式测试，不新增手机/其他硬件目标。现有 Go 与原生 Rime 行为没有变化，因此本次不运行安装、真实 Rime 或注册宿主验收。

[本轮验证记录](VALIDATION.md) · [最小事件协议与 Go/Broker 适配设计](PROTOCOL.md) · [硬件尺寸、误触和延迟说明](HARDWARE.md)

# test.13 本地候选：宿主注册表长度与字体退出修复

本轮是本地分支候选，尚未推送、合并或经过本轮 GitHub CI，未安装；D1/D2 仍未执行。
产品提交为 `ff1a3d9269c0061c0582bb2f707cfc2d8a68a6bb`。独立宿主在后续提交固定下表身份，产品提交与宿主提交须分开记录。

## 修复与回归

- 宿主注册路径读取按第二次 `RegGetValueW` 实际返回字节数缩短缓冲区，再检查终止符与嵌入 NUL。保留 REG_SZ、64 位视图、optional 缺失规则和失败停止边界。126/126、128/126（零/非零尾部 padding）、奇数/超界长度、缺终止符、空值、嵌入/重复 NUL 和 API 失败均覆盖。隔离变异仅移除缩短操作，128/126 用例准确失败。
- 前端以类型化指针持有私有字体路径至退出，在实际 API 调用时转换地址并保活。真实 FR_PRIVATE 字体装卸与 GC/分配压力三轮通过，独立额外 Remove 返回 0，证明测试中的注册已移除；旧 uintptr 等价夹具失败。该夹具不是原安装版崩溃的重新复现。
- Go 1.25.14 Windows/amd64：前端 142 个顶层测试和 132 个子测试通过，touchkeyboard 9 项通过。既有 `TestTouchBridgePersistentOwnHostUI`、`TestPreviewCompleteCorpus` 两项 opt-in 跳过。
- C++ 四目标构建、3/3 phase-A 离线 suite（含实际 8.3 别名）通过；完整包构建时另运行五项原生内存/策略检查和全量资源 Broker 输入检查，全部通过。
- 前端包装 9 项回归通过。扩大组装/生命周期/包装回归时 34 项通过，既有 `test_linked_input` 因普通权限无法创建符号链接夹具（WinError 1314）报错，原日志保留。此项未记通过，安装前仍须由具备该能力的 CI 完整验证；未提权或更改系统设置。
- 同一候选前端曾以 `--preview --touch-ui --theme dark --window-sizing fit` 启动一次，只点击正常“退出”：exit 0、stderr 空、窗口消失。这是候选本地预览退出观察，不是已安装 TSF 输入、普通应用或稳定性验收。

## 固定完整候选

| 身份 | SHA-256 |
| --- | --- |
| 本地外层交付 ZIP | b55b004795261acb3a690a2c6ebaea57f81e31d72c061d14dafd5db8a792df1a |
| 内层 test.13 安装 ZIP | 51d61513811eb1080f2aba30cd01555c52cab5498307cd4d47e720b01cd12a22 |
| installed-18u-product.json | dbc12369d3ca1de81d3dd96a6fd543794951edc3689a098c0c113c17577d217e |
| frontend/YimeTouchKeyboard.exe | f13adbaae8475cf0cae8d54b1e94b4e7cabe8caf63274d20785958a5e76ca3a4 |
| x64/YimeTextService18u.dll | 2ce9ae68566a4a4b2d9a830f6c52f4c051e52dba1373c0ea05c48a4a6c9470f4 |

本地外层 `C:\dev\d1d2-r2\candidate-test13\test13-local-fixed-package.zip` 仅含内层 `YimeCore-18u-0.1.0-18u-test.13-windows-amd64.zip`，不是 GitHub artifact，也不包含随后构建的宿主或计划。独立宿主和计划另行交付，避免哈希自引用。完整记录在同目录 `package-identity.json` 及 `C:\dev\d1d2-r2\evidence`。

六个 PE 均为 AMD64，签名状态单独记录；完整文件、descriptor、同源前端/TIP v2 协议及 ZIP 逐文件校验完成。这不等于安装或发布者信任成立。

## 原始失败与后续计划

原 test.12 包、PR #111 宿主、D1/D2 原计划和原始失败证据保持不变。旧 D1 仅预检尝试一次，因 `registered DLL path` 在 COM/TSF 前阻断；旧 D2 未启动。前端退出访问冲突单独记录，不能当作 D1/D2 注入结果。原证据 ZIP SHA-256 为 `f9fe02039292a5567a05cbafc5b20047cd11d92f51f709dc16b2efa3537d8ad0`。

新计划保持 D1 一次确认“你好”、异步写锁延迟 350 ms；D2 一次确认“测试”、修改前 E_FAIL。各使用新 runId/新输出目录，`allowManualRecovery=false`，120 秒上限，触发后至少六秒观察。宿主真实执行仍必须匹配普通权限、机器、注册路径、已加载模块、profile/context 和前台身份。

安装另行执行。先补齐 CI，按完整包维护并核验实际安装身份，再开始新 D1/D2。当前已安装 test.12 不能通过新宿主的 test.13 固定身份门禁；不得单独替换前端或改计划冒充已升级。自动化接口会激活被点击窗口，实际原生批次须由真人鼠标保持宿主前台完成候选确认；本机鼠标范围不扩展为手指/笔验收。

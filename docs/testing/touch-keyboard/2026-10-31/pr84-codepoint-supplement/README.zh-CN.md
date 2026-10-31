# PR84 宿主字符级证据最小补充

仅补充 [PR84 原始记录](../../2026-10-30/pr83-desktop-mouse/README.zh-CN.md)，不改写旧反馈。原 PR 已合并为 `a562e3bc2b94624ce7b4ff944fbac21dd0c761da`。工具自测不是宿主验收；模板维持 pending。2026-10-31 完成的四项补测见[实际结果](RESULTS.zh-CN.md)，区分 Word COM 回读和 Firefox 用户截图编码行。

## 最少操作

先检查原一次性测试文本是否仍在，若在且能确认来自原固定包，直接读取，不重新输入。已丢失的文本才补一次对应输入，并注明是新补测，不冒充10月30日原记录。分两批：Word W01/W02；Firefox WOW64 W01/W02。不重跑基础、E05—E12、触屏或笔项目。

仍使用 CI `41018028276` 的 amd64 包，sourceCommit `f01326e6c1976a4e67c9ff59693effc0e1110b1a`，exe SHA256 `0e24a31e2088c5b19e39bae8ac78adcc28a9cb258d2f0034b2addac1ec8cbc07`。操作者确认运行路径；换包停止此记录流程，不能拿新 main 包补旧包验收。

| 项目（每个宿主各一次） | 缺文本时才执行 | 完整预期 | 标量数 |
|---|---|---|---|
| W01 | 空框/新文档定位绑定，输入12；3次 Shift→N25，第一候选 | U+0031 U+0032 U+2026 | 3 |
| W02 | 独立空框/新文档定位绑定，输入12；6次 Shift→N25，第二候选 | U+0031 U+0032 U+22EF U+22EF | 4 |

保持 CN、变码、标点入口关闭；每个中点重新点击 Shift。选定后不再点键，观察正文不继续增长再回读。异常保留原文/码点，记录 failed，不自动重试。字符序列完全相等才排除本次最终文本中的重复/额外字符；不能据此推断没有发生过相同文本替换事件或未来延迟写入。

## Firefox：复用原测试页

打开已归档的 [test-textarea.html](../../2026-10-30/pr83-desktop-mouse/test-textarea.html)，不改HTML。先确认当前 Firefox 仍为 x86/WOW64（旧 PID 仅属历史记录）。页面编码行可直接显示完整3/4字符预期；保留正文和编码行截图。出现末尾省略提示表示超12字符，直接失败，不把截断前缀当通过。

若要保存完整正文、长度并可靠发现隐藏/超12字符，在该测试页开发者工具控制台执行以下只读表达式，将返回JSON原样另存为新文件。检查当前页确为该本地测试页；不启用任何绕过粘贴保护设置。W02 只改第一行的 W01 为 W02：

```javascript
(() => {
  const caseId = 'W01';
  const field = document.getElementById('test-text');
  if (!field || document.title !== '触屏输入临时测试') throw Error('Wrong test page');
  const actualText = field.value;
  const expectedText = caseId === 'W01' ? '12\u2026' : '12\u22ef\u22ef';
  const cps = s => Array.from(s, c => 'U+' + c.codePointAt(0).toString(16).toUpperCase().padStart(4, '0'));
  return JSON.stringify({caseId, capturedAt: new Date().toISOString(), url: location.href,
    actualText, actualCodepoints: cps(actualText), scalarCount: Array.from(actualText).length,
    displayedDiagnostic: document.getElementById('codepoints').textContent,
    expectedText, expectedCodepoints: cps(expectedText), exactMatch: actualText === expectedText,
    readMethod: 'read-only textarea.value', acceptanceStatus: 'pending-operator-review'}, null, 2);
})()
```

开发者工具夺焦可能清理键盘暂存，因此只能在确认已提交后回读。表达式不修改正文，也不从剪贴板冒充宿主读取。截图和JSON与结果模板关联，包身份、宿主版本/运行架构需另记；JS不能证明WOW64。

## Word：只读完整正文

脚本使用 Windows PowerShell **5.1** 的 GetActiveObject 附加现有 Word，不启动/关闭Word，不编辑、保存或选择正文。明确传入一次性**未保存**测试文档名称，拒绝已有路径的文档；不要传用户工作文档。多个Word实例有歧义时停止，不自动另开实例。读的是正文故事，不包括页眉或文本框；测试必须在普通正文中。

只去掉 Word 必带的最后一个 U+000D 段落结束符，原始文本及完整原始码点仍保存；其它换行、空格、不可见字符全部参与比较，不做 Trim/Normalize。输出以 CreateNew 创建，不覆盖已有记录。

在仓库根目录创建参数JSON（路径自行填写，OutputPath 的父目录应已存在）：

```json
{
  "CaseId": "W01",
  "DocumentName": "文档1",
  "KeyboardExe": "C:\\dev\\pr83-ci-delivery-41018028276\\amd64\\YimeTouchKeyboard.exe",
  "OutputPath": "C:\\dev\\pr83-ci-delivery-41018028276\\records-desktop-mouse\\word-W01-codepoints-attempt1.json"
}
```

```text
python tools/powershell/run_checked.py --edition ps5 --script docs/testing/touch-keyboard/2026-10-31/pr84-codepoint-supplement/Read-WordCodepoints.ps1 --params-file <参数JSON绝对路径>
```

W02 替换 CaseId、文档名及新输出文件名。若Word未注册到ROT或名称不匹配，记录读取失败；不把工具错误记作输入失败，也不自动重跑输入。脚本核对exe文件哈希，但不证明该程序产生正文，须由操作者在结果模板确认包路径/进程。

## 结果和范围

复制 RESULT_TEMPLATE.json 到独立结果目录。四项初始 pending；填实际正文、完整码点、证据路径/哈希、读取时间、宿主版本/进程架构及包来源。检查 exactMatch 与原始文本后才设置 passed/failed；不能仅凭工具自测、旧反馈或模板预期填 passed。保留每次失败，不覆盖原 PR84 文件。不扩大为触屏、触控笔、ARM64或已安装输入法结论。

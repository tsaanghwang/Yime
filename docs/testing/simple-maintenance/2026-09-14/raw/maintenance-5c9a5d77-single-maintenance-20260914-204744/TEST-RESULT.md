# 维护收尾结果：单独安装、卸载及重启恢复条件

包：maintenance-5c9a5d77；测试日期：2026-09-14。旧报告与失败记录保留。

## 用户最新确认

“单独安装和单独卸载，如果出错，重启后不切换到对象输入法，都可以。”

据此记录两产品单独安装、单独卸载可完成；遇错时，用户验证的恢复方式为正常重启后不切换到待维护的输入法，再执行维护。这是本测试机的实测条件，不是任意错误或其他机器的通用保证。

## 日志核对

- Core 单独安装：cdae51515ce340e9bce7e0d7306b1948，18:04:18 完成，退出 0。
- Core 卸载两次受阻：f4088e9d12ad413b9a07e23c9f1031d0、a39a1308c5c741ecbbb591743cee5565，日志为 YimeTextServiceExperiment.dll 无法独占读写，在等待文件释放阶段取消，退出 2。
- Core 最终卸载：95d44c9c7a914de5bff676370b5fe040，20:28:51 完成，退出 0。
- Rime/PIME 单独安装：59567341208a402191a9935ccf6d238a，20:29:33 完成，退出 0。
- Rime 卸载受阻：94463f25f8fa45a0bfd9b4cdb3bc46ef，日志为 PIMETextService.dll、YinYuan-Regular.ttf 无法独占读写，在等待文件释放阶段取消，退出 2。
- Rime 最终卸载：1ac9349fc4ea4e4e938d1e5eea181c1d，20:44:22 完成，退出 0。
- 两产品安装都直接返回 0；本轮日志中观察到的受阻发生在卸载。未定位具体文件占用进程，不凭独占打开失败排除其他访问原因。重启及未切换输入法的条件来自用户反馈。

## 总体状态

- Both 安装与外层正常结束：此前日志通过；重启前后两套切换输入正常：此前用户确认。
- 交叉卸载后留下的另一套可输入，装回正常：此前两方向均由用户确认；受阻后恢复记录保留。
- 两套卸载：此前重启后成功；单独安装和卸载：本次完成，保留卸载受阻和重启恢复条件，不表述为使用后无需重启即可立即维护。
- 单独安装期间的具体输入测试及应用名称：本条明确确认的是安装/卸载，未明确单装输入细节；不自动补写 Word/Codex 或单装输入验收全部通过。
- 最终安装状态：日志中两套均已卸载；当前目录观察见 directory-observation.json。输入法条目、安装条目 UI 未独立核验。

仅进行日志读取、目录只读检查及归档，未重新执行维护、修改脚本、删除用户数据或变更默认输入法。

## 原始日志摘要

### 07df5d92d94343949f4afcf50821fe56.user.log

开始时间：20260914204408

```text
Action: Check; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\rime-pime
```

### 16c637f18c394935b01b1c5109ecf2ac.user.log

开始时间：20260914203535

```text
Action: Check; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\rime-pime
```

### 1ac9349fc4ea4e4e938d1e5eea181c1d.admin.log

开始时间：20260914204416

```text
Action: Uninstall; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\rime-pime
Uninstalled. Other products were not removed.
```

### 1ac9349fc4ea4e4e938d1e5eea181c1d.user.log

开始时间：20260914204411

```text
Action: Uninstall; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\rime-pime
Elevated setup exit code: 0
```

### 59567341208a402191a9935ccf6d238a.admin.log

开始时间：20260914202926

```text
Action: Install; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\rime-pime
Installed: Yime Rime-PIME. Select it from the Windows input-method menu.
```

### 59567341208a402191a9935ccf6d238a.user.log

开始时间：20260914202921

```text
Action: Install; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\rime-pime
Elevated setup exit code: 0
```

### 62384e37c35444ad86a2d2e62ce50a9e.user.log

开始时间：20260914180637

```text
Action: Check; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\yimecore
```

### 94463f25f8fa45a0bfd9b4cdb3bc46ef.admin.log

开始时间：20260914203543

```text
Action: Uninstall; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\rime-pime
Files unavailable under C:\Program Files\Yime Rime-PIME: PIMETextService.dll, YinYuan-Regular.ttf
FAILED stage: wait for installed files to be released
Setup exit code: 2
```

### 94463f25f8fa45a0bfd9b4cdb3bc46ef.user.log

开始时间：20260914203538

```text
Action: Uninstall; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\rime-pime
Elevated setup exit code: 2
```

### 95d44c9c7a914de5bff676370b5fe040.admin.log

开始时间：20260914202846

```text
Action: Uninstall; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\yimecore
Uninstalled. Other products were not removed.
```

### 95d44c9c7a914de5bff676370b5fe040.user.log

开始时间：20260914202840

```text
Action: Uninstall; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\yimecore
Elevated setup exit code: 0
```

### a39a1308c5c741ecbbb591743cee5565.admin.log

开始时间：20260914180731

```text
Action: Uninstall; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\yimecore
Files unavailable under C:\Program Files\YimeCore: YimeTextServiceExperiment.dll
FAILED stage: wait for installed files to be released
Setup exit code: 2
```

### a39a1308c5c741ecbbb591743cee5565.user.log

开始时间：20260914180726

```text
Action: Uninstall; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\yimecore
Elevated setup exit code: 2
```

### a42cce5e394e4293a879c20824ec0a5a.user.log

开始时间：20260914202918

```text
Action: Check; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\rime-pime
```

### cdae51515ce340e9bce7e0d7306b1948.admin.log

开始时间：20260914180413

```text
Action: Install; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\yimecore
Installed: YimeCore. Select it from the Windows input-method menu.
```

### cdae51515ce340e9bce7e0d7306b1948.user.log

开始时间：20260914180408

```text
Action: Install; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\yimecore
Elevated setup exit code: 0
```

### ecebc70c2204448eb538595f3098e5d0.user.log

开始时间：20260914180724

```text
Action: Check; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\yimecore
```

### f3aad0ba5f334ec09d159a832f774d5d.user.log

开始时间：20260914180405

```text
Action: Check; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\yimecore
```

### f4088e9d12ad413b9a07e23c9f1031d0.admin.log

开始时间：20260914180646

```text
Action: Uninstall; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\yimecore
Files unavailable under C:\Program Files\YimeCore: YimeTextServiceExperiment.dll
FAILED stage: wait for installed files to be released
Setup exit code: 2
```

### f4088e9d12ad413b9a07e23c9f1031d0.user.log

开始时间：20260914180639

```text
Action: Uninstall; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\yimecore
Elevated setup exit code: 2
```

### fc32e1473acc4ca9a29307030ec124b4.user.log

开始时间：20260914202838

```text
Action: Check; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\yimecore
```

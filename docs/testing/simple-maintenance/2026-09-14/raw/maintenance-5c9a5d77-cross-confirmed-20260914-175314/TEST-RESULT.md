# 维护收尾进度：交叉卸载与装回

包：maintenance-5c9a5d77。记录日期：2026-09-14。原报告和原始日志保留。

## 用户反馈

“卸载 core 版，rime 版能用，装回正常。马上卸载 rime 版出错，重启后卸载 rime 版成功，装回正常。”

## 结果与证据边界

- NEXT-MAINTENANCE 步骤 1：最终卸载 Core、留下的 Rime 输入、Core 装回正常，用户确认；成功卸载日志 1ee1cd3d5a6a4a25af1017f6df3480e1 和装回日志 c362adee7de74091a496b786d841875f 均退出 0。另保留较早 c8ff4ac7d74f48f78227c9c003c1aca0 的文件无法独占读写后取消（退出 2），不能写作全程无失败。
- 步骤 2：Rime 卸载三次受阻后取消（e45bae28992a48e2a7d075142a8511ba、06fb7d98309048feb8d71e5844b121fa、86f390c126904baa918d9e96915bdf00），均退出 2。日志列出 PIMETextService.dll、YinYuan-Regular.ttf 无法独占读写，失败阶段为 wait for installed files to be released，未进入后续注销/删除。具体占用进程未定位，不能仅凭日志排除写权限问题。
- 用户报告重启后卸载 Rime 成功；日志 26e1f2b69f81459aad48c28a67d88f72 退出 0，17:43:45 完成。装回日志 57812feedac7462ca7f662045b581343 退出 0，17:45:48 完成，x86/x64 注册检查通过；用户报告装回正常。
- Rime 已卸载、尚未装回期间，留下的 Core 输入正常：用户针对该项追问明确回复“正常”，据此记录通过。步骤 2 的卸载、另一产品输入、装回均已完成；重启前受阻取消的记录仍保留。
- 实际输入应用名称未提供，不补写 Word/Codex 各自通过。
- 当前两套已装回（据日志和用户反馈），不是最终两套均卸载状态。
- 步骤 3（卸载两套并确认条目/目录移除）、4（Core 单装输入后卸载）、5（Rime 单装输入后卸载）：尚未确认。

本轮只读取安装维护日志并归档；未修改包、操作安装/卸载或终止进程。后续成功不覆盖之前受阻取消的原始记录。

## 日志摘要

### 06fb7d98309048feb8d71e5844b121fa.admin.log

开始时间：20260914173651

```text
Action: Uninstall; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\rime-pime
Files unavailable under C:\Program Files\Yime Rime-PIME: PIMETextService.dll, YinYuan-Regular.ttf
FAILED stage: wait for installed files to be released
Setup exit code: 2
```

### 06fb7d98309048feb8d71e5844b121fa.user.log

开始时间：20260914173646

```text
Action: Uninstall; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\rime-pime
Elevated setup exit code: 2
```

### 1ee1cd3d5a6a4a25af1017f6df3480e1.admin.log

开始时间：20260914171105

```text
Action: Uninstall; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\yimecore
Uninstalled. Other products were not removed.
```

### 1ee1cd3d5a6a4a25af1017f6df3480e1.user.log

开始时间：20260914171058

```text
Action: Uninstall; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\yimecore
Elevated setup exit code: 0
```

### 26e1f2b69f81459aad48c28a67d88f72.admin.log

开始时间：20260914174339

```text
Action: Uninstall; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\rime-pime
Uninstalled. Other products were not removed.
```

### 26e1f2b69f81459aad48c28a67d88f72.user.log

开始时间：20260914174333

```text
Action: Uninstall; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\rime-pime
Elevated setup exit code: 0
```

### 34d4583ed41a422395ac341ba11315f1.user.log

开始时间：20260914170908

```text
Action: Check; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\yimecore
```

### 3d6671215d604c0d9798cc8127b4e4cf.user.log

开始时间：20260914173801

```text
Action: Check; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\rime-pime
```

### 3da5e5025de140428ecef554c8ebc03d.user.log

开始时间：20260914171055

```text
Action: Check; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\yimecore
```

### 572a03aee7c3442bb5d6732781d7de60.user.log

开始时间：20260914173644

```text
Action: Check; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\rime-pime
```

### 57812feedac7462ca7f662045b581343.admin.log

开始时间：20260914174541

```text
Action: Install; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\rime-pime
Installed: Yime Rime-PIME. Select it from the Windows input-method menu.
```

### 57812feedac7462ca7f662045b581343.user.log

开始时间：20260914174536

```text
Action: Install; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\rime-pime
Elevated setup exit code: 0
```

### 59cd039887234d4e9e11a0a85c0c4e94.user.log

开始时间：20260914173513

```text
Action: Check; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\rime-pime
```

### 86f390c126904baa918d9e96915bdf00.admin.log

开始时间：20260914173811

```text
Action: Uninstall; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\rime-pime
Files unavailable under C:\Program Files\Yime Rime-PIME: PIMETextService.dll, YinYuan-Regular.ttf
Files unavailable under C:\Program Files\Yime Rime-PIME: PIMETextService.dll, YinYuan-Regular.ttf
Files unavailable under C:\Program Files\Yime Rime-PIME: PIMETextService.dll, YinYuan-Regular.ttf
FAILED stage: wait for installed files to be released
Setup exit code: 2
```

### 86f390c126904baa918d9e96915bdf00.user.log

开始时间：20260914173804

```text
Action: Uninstall; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\rime-pime
Elevated setup exit code: 2
```

### 87a01c04faf04277854880d6c530b008.user.log

开始时间：20260914171344

```text
Action: Check; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\yimecore
```

### 8ce48b4fc9d44643b924b236126c0117.user.log

开始时间：20260914174331

```text
Action: Check; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\rime-pime
```

### 8db825c0794b4874856ab9eb51449f6d.user.log

开始时间：20260914174533

```text
Action: Check; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\rime-pime
```

### c362adee7de74091a496b786d841875f.admin.log

开始时间：20260914171353

```text
Action: Install; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\yimecore
Installed: YimeCore. Select it from the Windows input-method menu.
```

### c362adee7de74091a496b786d841875f.user.log

开始时间：20260914171347

```text
Action: Install; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\yimecore
Elevated setup exit code: 0
```

### c8ff4ac7d74f48f78227c9c003c1aca0.admin.log

开始时间：20260914170918

```text
Action: Uninstall; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\yimecore
Files unavailable under C:\Program Files\YimeCore: YimeTextServiceExperiment.dll
FAILED stage: wait for installed files to be released
Setup exit code: 2
```

### c8ff4ac7d74f48f78227c9c003c1aca0.user.log

开始时间：20260914170911

```text
Action: Uninstall; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\yimecore
Elevated setup exit code: 2
```

### e45bae28992a48e2a7d075142a8511ba.admin.log

开始时间：20260914173523

```text
Action: Uninstall; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\rime-pime
Files unavailable under C:\Program Files\Yime Rime-PIME: PIMETextService.dll, YinYuan-Regular.ttf
FAILED stage: wait for installed files to be released
Setup exit code: 2
```

### e45bae28992a48e2a7d075142a8511ba.user.log

开始时间：20260914173516

```text
Action: Uninstall; package: C:\Users\Golde\Yime Simple Test Archives\simple-delivery-20260914\maintenance-5c9a5d77\Yime-Maintenance\rime-pime
Elevated setup exit code: 2
```

## 后续确认

用户明确确认 Rime 卸载后 Core 输入正常。两项交叉卸载后另一产品仍能输入及装回正常均已有用户确认；具体应用名称仍未细分。本文为增补版本，原报告保留。

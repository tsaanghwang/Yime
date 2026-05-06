# 最小试用交付方案

这份说明把当前“试用 / 分发路径”收成一个默认方案，目标只有一个：

- 让你下次给朋友发试装包时，不再手工拼安装包、说明文档和反馈模板。

## 当前默认交付形态

当前推荐的最小可交付方案是：

- 一个 `Setup.exe`
- 一页给试用者看的最小说明
- 一份发包前自检清单
- 一段发给朋友的短消息模板

这些文件统一收进：

- `dist/friend-trial/`

## 一键构建入口

仓库已提供：

- `scripts/build_friend_trial_package.bat`

最短路径：

```bat
scripts\build_friend_trial_package.bat
```

这个脚本会自动：

1. 调用 `scripts/build_setup_release.bat`
2. 生成 `dist/setup/Yime-Setup-<version>.exe`
3. 新建 `dist/friend-trial/`
4. 把安装包和 3 份试用文档一起复制进去

## 产物内容

成功后，`dist/friend-trial/` 里会有：

- `Yime-Setup-<version>.exe`
- `FRIEND-TRIAL-START-HERE.md`
- `FRIEND-TRIAL-CHECKLIST.md`
- `FRIEND-TRIAL-MESSAGE-TEMPLATE.md`
- `README.txt`

## 这套方案适合什么场景

适合：

- 第一次给外部朋友试装
- 你想优先确认“能装、能开、能唤起、能上屏”
- 你还不准备做更正式的发布体系

## 这套方案暂时不覆盖什么

- 自动更新
- 数字签名
- 更复杂的安装向导定制
- 系统级输入法注册

也就是说，它解决的是“最小可发”，不是“正式产品发布”。

## 配套文档关系

- `friend-trial-one-page.md`：给试用者看的一页说明
- `friend-trial-checklist.md`：发包前自己先过一遍的清单
- `friend-trial-message-template.md`：发给朋友时可直接改写的短消息
- 本文：定义默认交付结构和统一构建入口

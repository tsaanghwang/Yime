# Yime 高级布局设计模块

本模块只编辑最后一级投影：`Yinyuan ID -> 可打印键`。它不允许从拼音直接指定键码，也不修改音元身份或拼音分解语义。

## 图形界面（推荐）

推荐从输入法的“工具中心 → 高级布局”打开。也可以直接双击构建产物 `build/go-backend/yime-layout-designer.exe`。图形界面可以：

- 在 Base / Shift 两层键盘图上查看当前映射；
- 选择键位和 Yinyuan ID，以交换方式调整布局；
- 用数字标调拼音即时试算等长、变长和简码；
- 打开“音节分解观察器”，筛选全部标准音节并逐项查看规范化、切分、四个 Yinyuan ID 和当前布局投影；
- 校验、预览全部派生文件，确认后再应用正式布局；
- 自动保存草案，并在正式布局已经变化时拒绝旧草案覆盖新结果。
- 从当前布局新建副本，并命名保存、载入或删除多个个人方案。

“试算三模式编码”只读取内存中的草案，不修改正式布局和词库。只有“确认应用布局”并再次确认后，才会启动完整重建流程。

“音节分解观察器”读取 `yime_syllable_decomposition.tsv`。该表由 Python 原型的真实结构化编码器全量生成，Windows 端只负责筛选和展示，不另写一套拼音切分规则。界面始终显示“当前显示数 / 全部音节数”，详情同时显示导出时键码和当前布局草案投影。

从工具中心打开时，官方共享数据始终只读。应用结果写入 `%APPDATA%\PIME\Rime` 的用户覆盖层，已存方案位于其 `yime_layouts` 子目录。应用过程依次完成完整生成、学习记录迁移、三套方案显式编译和运行时刷新通知；构建或校验失败会恢复原覆盖文件。

这里的“三套”按输入模式划分为等长、变长和省键。每一种模式都同步包含：从初始词库重建的系统词典、从 `yime_user_phrases.txt` 按新码表重建的用户自建词表，以及按字词和原学习统计迁移的 Rime 学习库。三类数据全部成功后才发出一次运行时刷新通知，三种模式不会分别切换到不同布局。

## 命令行（自动化可选）

图形界面使用同一套后端。脚本或自动化任务也可以调用：

```powershell
cd C:\dev\Yime\go-backend
go run ./cmd/yime-layout-designer draft -output .\layout-trial.json
go run ./cmd/yime-layout-designer assign -layout .\layout-trial.json -id M16 -key t
go run ./cmd/yime-layout-designer validate -layout .\layout-trial.json
go run ./cmd/yime-layout-designer preview -layout .\layout-trial.json
go run ./cmd/yime-layout-designer apply -layout .\layout-trial.json -accept
```

`assign` 使用交换语义，始终保持 57 个 Yinyuan ID 与 57 个键一一对应。`apply` 先在临时目录重建并验证下列完整集合，全部成功后才原子替换：

草案保存其所基于的正式布局摘要；如果其他维护者已经改变正式布局，旧草案会被拒绝，不能覆盖新结果。同一时间也只允许一个生成流程持有布局锁。

- `yime_yinyuan_layout.json`
- `yime_pinyin_codes.tsv`（显式保存 full / variable / shorthand）
- 三套 Rime 词典
- 三套 schema 的 `alphabet`、版本和布局专属 `user_dict`
- `yime_lexicon_manifest.json`

部署后，现有 `learningmigration` 模块会把旧布局学习记录迁移到新布局命名空间。任何旧码不能通过旧布局反解为 Yinyuan ID、或任何学习词条不能在新词典中匹配时，流程会保留旧库并停止切换。

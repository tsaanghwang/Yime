# PSC 轻声、儿化规范来源低频外围候选

## 目的

把已经复核、但尚未进入 1,166,300 条运行核心的 PSC 轻声和儿化“词形—注音对”纳入可选范围，
同时不借 PSC 材料裁决规范主读，不改变核心词典文件、核心权重或既有高频排序。

## 当前范围

- 来源记录：315 条；
- `psc_neutral_tone`：183 条；
- `psc_erhua`：132 条；
- 等长、变长、省键三模式：每模式 315 条；
- 统一外围权重：`1`；
- 已在核心中存在的同“文字—模式编码”记录：0 条。

筛选只接受 `machine_verified`、`confirmed` 或 `corrected` 状态。儿化记录还要求候选文字明确写出
“儿”；“文字未写儿的口语儿化提示”和待复核记录继续留在来源数据库，不进入运行候选。

## 排序与数据边界

外围候选使用独立的 `table_translator@psc_peripheral` 和独立词典，`initial_quality` 为 `-1`，词典
权重固定为 `1`。因此它们只补充“能输入”，不会写入、重排或重新生成高频核心。三模式编码均由
同一规范数字调记录经正式音节码表和 `codemode.BuildRecord` 派生，不手写模式编码。

这一层保存的是有规范来源的候选读法，不等于批准轻声表层调值、融合儿化或能产儿化规则。来源记录
仍不是“主要读音”判决；以后完成更严格审音后，可逐条提升、替换或整批删除本外围层。

## 产物与门禁

- `psc_pronunciation_peripheral_source.json`：筛选后的可追溯来源快照；
- `yime_psc_peripheral_{full,variable,shorthand}.dict.yaml`：三模式运行附加词典；
- `yime_psc_peripheral_manifest.json`：输入、输出哈希、计数与完整性门禁；
- `yime_psc_peripheral_{full,variable,shorthand}.schema.yaml`：Rime 依赖方案。

生成器拒绝来源主读标记、未复核记录、缺少正式音节码、重复来源对和三模式派生失败，并在生成前后
哈希核心三模式词典，以确保核心文件未被修改。

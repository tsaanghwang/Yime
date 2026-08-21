<!-- markdownlint-disable MD013 -->
# 噪音类与乐音类：分类说明

## 文档地位

本文是本仓库关于噪音类与乐音类的唯一分类定义。它同时约束中文说明、英文说明、Python 类型、Yinyuan ID 数据和 AI 对代码的解释。

如果旧文档把两类直接等同于普通声学中的“噪声／乐音”、`unpitched/pitched`，或者仅根据有没有物理基频分类，以本文为准。

## 唯一名称

| 用途 | 第一类 | 第二类 |
|---|---|---|
| 中文规范名 | 噪音类 | 乐音类 |
| 英文规范名 | `zaoyin` | `yueyin` |
| Python/JSON 标识 | `zaoyin` / `ZAOYIN` | `yueyin` / `YUEYIN` |
| Yinyuan ID 前缀 | `N` | `M` |

`noise`、`musical sound`、`unpitched` 和 `pitched` 都不是规范名称。它们只可以用来解释历史类名或旧数据字段，不能用来重新定义两类。

正式英文正文第一次出现时写作 `zaoyin class` 和 `yueyin class`，随后可以直接写 `zaoyin`、`yueyin`。不要为了让名称看起来熟悉而换成带有其它既定含义的普通英语术语。

## 分类定义

**噪音类（zaoyin）** 是音质构成区别特征，而音高为零、不确定、不稳定或不构成该片音及音元区别特征的类别。

**乐音类（yueyin）** 是音质和可确定音高共同构成该片音及音元区别特征的类别。

分类关键不是物理上“有没有声带基频”，而是音高是否作为可确定的区别特征参与归类。

因此：

- 清辅音没有声带基频，归噪音类；
- 浊首音可能具有实际音高，但该音高不承担首音音元的区别作用，仍归噪音类；
- 干音中的乐音类片音由音质部分及与其联结的可确定调段构成，音质和音高共同参与区别，归乐音类。

## 从分析结果到顶层类别

噪音类／乐音类首先是根据片音区别特征结构归纳出的分类结果：

```text
片音的音质、音高及其区别作用
  -> 判断区别特征结构
  -> 归类为 zaoyin 或 yueyin
```

分类一旦确定，`zaoyin/yueyin` 又成为片音层、音元层和编码层共享的顶层类别轴：

```text
分类结果
  -> Pianyin.category
  -> Yinyuan.category
  -> Yinyuan ID 的 N/M 类别
  -> 编码结构校验
```

所以，“由分析归纳出两类”和“把两类作为下游顶层分类”并不矛盾。前者说明类别从哪里来，后者说明已经得到的类别怎样贯穿程序。

## 类别轴与结构轴

类别轴和音节结构轴必须分开：

```text
结构轴：首音 / 干音 / 呼音 / 主音 / 末音
类别轴：zaoyin / yueyin
```

在当前现代通用汉语模型中：

```text
首音位置       <- zaoyin 类音元
呼/主/末位置   <- yueyin 类音元
```

这是当前语言模型中的稳定填充关系，不是术语同义关系。不得写成“首音就是噪音”或“干音就是乐音”。

## 理论分析链与当前工程链

理论上的分类链从可发、可听知的片音及其特征出发。当前生产程序不从录音重新测量特征，而是执行已经审查并登记的分类结果：

```text
带调拼音
  -> 首音/干音结构分析
  -> 首音查得 N 类 Yinyuan ID
  -> 干音查得三个 M 类 Yinyuan ID
```

因此，代码中的 `YinyuanCategory` 是分类结果的共享类型，不是声学分类器。仅根据内部 `pitch` 字段的数据类型恢复类别，只能作为兼容旧对象的标记解释，不能冒充理论分类规则。

## 代码约束

1. 新代码使用 `ZaoyinPianyin`、`YueyinPianyin`、`ZaoyinYinyuan`、`YueyinYinyuan` 和 `YinyuanCategory`。
2. `UnpitchedPianyin`、`PitchedPianyin`、`NoiseYinyuan`、`MusicalYinyuan` 只作为兼容旧调用的别名或内部历史基类，不得在新 API 和说明中继续扩散。
3. 类别由规范对象类型或经过审查的语义注册表明确给出；不得把“有任意 pitch 值”直接当作乐音类的充分条件。
4. `Nxx`、`Mxx` 是已经分类后的 Yinyuan ID，不是分类依据本身。
5. `zaoyin/yueyin` 是片音层和音元层共享的类别名，不是首音、干音等结构段名。

英文版见 [Zaoyin and Yueyin: Classification Specification](ZAOYIN_YUEYIN_CLASSIFICATION_EN.md)。片音、音元和 Yinyuan ID 的层次见 [片音分析与音元表示：工程阅读概要](PIANYIN_ANALYSIS_OVERVIEW.md)。

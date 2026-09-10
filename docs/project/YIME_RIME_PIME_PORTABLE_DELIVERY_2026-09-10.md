# Rime/PIME 独立候选离线交付

影响产品：Rime/PIME。YimeCore 保持当前安装。此交付整理现有 09-09 候选，不重新构包，不提升安装、签名或公开发布验收。

交付目录：`%USERPROFILE%\Yime Rime-PIME Delivery Archives\candidate-20260910-3096da82`，ZIP 位于同级 `candidate-20260910-3096da82.zip`，大小 41,570,661 字节。

- ZIP SHA-256：`dfe91b811030501fc2441114d8df612ae0114a670b3e033fe9b957556ab3fbd7`
- 原始 delivery index SHA-256：`983f7e98f58b6ebf13ba2b5f309a2056eb770fc6384a12c7d64c222f650d8947`
- 安装器 SHA-256：`3096da82a02e78b1d411ea554fcc9eeaddb45e6c6c746be64b803a261d2b65fa`

包内保留原始索引及六个原字节工件：安装器、build receipt、candidate manifest、static payload、source baseline 和 source inventory；另附独立 Python 核验脚本及说明。索引中的 `.tmp/...` 是交付目录内保留的相对路径，不依赖接收机存在开发仓库。ZIP 不含用户数据或审批文件。

接收者先从本记录核对 ZIP 哈希，再解包；从解包目录运行：

```text
python verify_delivery.py . --expected-index-sha256 983f7e98f58b6ebf13ba2b5f309a2056eb770fc6384a12c7d64c222f650d8947
```

核验脚本检查索引独立 pin、六工件的原始字节和收据跨文件绑定，拒绝路径越界及间接子路径，始终返回 `execution_authorized=false`。其通过不代表对 PE、签名、所有包内成员或实际宿主的重新验收；既有完整验证保留原记录。

验证包括合成破坏输入测试，以及从 ZIP 解包到新临时目录后，仅运行包内脚本核验六工件。没有执行安装器、产品进程或系统注册操作。

实际下一步仍为获准干净独立 x64 Windows 的首装/注册/就绪及回滚卸载验收。当前“计算机”已装 YimeCore，不属于该候选首装环境；不删除其 YimeCore 以凑出干净目标。没有确定目标时，保留交付介质，继续源码工作。目标确定后还须绑定机器身份、发起 SID、候选收据、原始审批和边界文件；这些值不能预填或由本核验生成授权。之后才进行 DP2 两种共存安装顺序和 DP3 三选一入口。

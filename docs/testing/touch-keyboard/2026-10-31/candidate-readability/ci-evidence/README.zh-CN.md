# PR #87 固定CI包证据

本目录按原始字节归档 [CI run 41178044364](https://github.com/tsaanghwang/Yime/actions/runs/41178044364) 的包元数据与包外检查记录。原始交付目录为 `C:\dev\Yime-deliveries\touch-keyboard-pr87-20261031`；[INDEX.json](INDEX.json) 逐项列出原始绝对路径、归档相对路径、字节数和SHA-256，共10个原始文件、40,397 bytes。归档时已重新核对每项原始字节和哈希。`.gitattributes` 禁止Git换行转换，保留已有CRLF。

PR分支头为 `8c7d26d67eff4b6650940b69963824141f565688`（`sourceHead`）；本次PR工作流实际检出并构建的是 `12a9930ce4e84b5c7de35fb2816c201b1e72e8af`（`checkoutCommit`，也是包内 `sourceCommit`）。两者是不同身份，固定包名称、清单和校验必须按后者核对；不能把包来源改写为分支头或后续提交。

CI上的amd64原生便携包检查通过，见 `records/amd64-ci-package-check.json`。同一轮ARM64固定包在ASUS测试机上的原生便携包检查及触屏数据检查通过，见 `records/arm64-package-check.json` 与 `records/arm64-touch-ui-check.json`。两架构ZIP摘要、PE架构、清单和资源完整性结果见 `records/package-identities.json`。这些检查没有发送宿主输入；此固定CI包的真人手指、触控笔、目视及真实宿主测试未做，不继承此前本地开发包的认可或通过。未安装输入法，未改变默认输入法或用户数据。

`reference/verify_pr87_delivery.py` 是验证过程脚本的原始副本，仅供审阅；它保留原 `.tmp` 位置所需的相对路径语境，不应直接从本归档目录运行。本目录不包含ZIP、程序/数据包、运行状态、下载脚本或 `.tmp/pr87-downloads.json`。已检查归档内容没有临时签名下载URL或凭据；保留的URL仅为GitHub运行记录和稳定artifact API地址。原始记录中的本机绝对路径、临时索引路径及开发检查元数据保持未改写。

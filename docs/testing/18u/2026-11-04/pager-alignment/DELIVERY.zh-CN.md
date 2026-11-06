# test.10 完整包：翻页键外沿对齐

日期：2026-11-04。固定源码 `853eb017eb5dcd5e05f67ff9db4b46bbbb94d0ed`，分支 `codex/msi-18u-test-preparation-20261103`。

左翻页键左边缘与各行首键左边缘对齐，右翻页键右边缘与各行末键右边缘对齐。保持翻页键宽高、候选数量和翻页行为，继承 test.9 启动自动适应屏幕。见[开发说明](DEVELOPMENT.zh-CN.md)。

[下载完整 test.10 Artifact](https://github.com/tsaanghwang/Yime/actions/runs/41793386958/artifacts/13305225670)，保留至 `2026-11-18T07:41:01Z`。

| 文件 | 字节数 | SHA-256 |
|---|---:|---|
| Artifact 外层 ZIP | 192203141 | `083f93a9f97ffdb7d3d6d623484158471d2d1ee8a57bb9c89a9ee1a86896b3d4` |
| `YimeCore-18u-0.1.0-18u-test.10-windows-amd64.zip` | 192164067 | `360542a35fb6eb18a2cd0a0abcad145f41a2b19e79f44bae71c1315dc1a3ce72` |
| `payload/frontend/YimeTouchKeyboard.exe` | 7882752 | `7e5db643ba455ec478eed23e2f2646530e397a87c58d18c32e11e363740fd116` |

本机完整包：`C:/dev/Yime/.generated/pager-alignment-development/YimeCore-18u-0.1.0-18u-test.10-windows-amd64.zip`。外层与产品 ZIP 哈希分别核对，包内 46 个成员全部核验；[下载记录](download-verification.json)、[源码与逐文件身份](ci-853eb017/package-evidence.json)、[CI 证据索引](evidence-index.json)。未执行包内程序或安装脚本。

- [Touch terminal prototype](https://github.com/tsaanghwang/Yime/actions/runs/41793387083)：success。
- [Installed 18u compile and offline checks](https://github.com/tsaanghwang/Yime/actions/runs/41793386958)：success。
- [Build](https://github.com/tsaanghwang/Yime/actions/runs/41793386771)：success。

本地现有完整前端回归和 7 项前端包装器检查通过，原生离屏绘制已确认左右对齐、九个候选完整可见；[本地证据](local-validation.json)。该结果属于开发验证，不代替真人触屏验收。

本机仍为 test.8。test.9 尚未安装，本次 test.10 同时包含自动适配与翻页键对齐，作为后续维护使用的完整匹配包；没有修改已安装文件、默认输入法或用户数据。

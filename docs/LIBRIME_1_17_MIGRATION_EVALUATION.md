# librime 1.17.0 迁移评估

## 结论

Yime 可以从官方 librime 1.16.1 迁移到 1.17.0。当前评估未发现 ABI、候选结果、
部署、分页、用户词典快照或竞态方面的不兼容。

正式迁移必须同时提交本文所述的两项工程约束：

1. Rime 共享数据作为仓库内固定资产随构建和安装发布，不依赖 Weasel、本机目录
   或构建时 Plum 下载。
2. `rime.dll`、`rime_deployer.exe` 和 `rime_dict_manager.exe` 由
   `rime_runtime.lock.json` 同时锁定版本、来源和 SHA-256；构建与运行时均执行门禁。

## 锁定版本

- librime：`1.17.0`，提交 `33e7814`
- Lua 插件：`ec52e48`
- octagram 插件：`dfcc151`
- predict 插件：`920bd41`
- 平台：官方 `Windows-msvc-x64`

| 文件 | SHA-256 |
|---|---|
| `rime.dll` | `86b4c7357d4c6d293ce5589b234d8859ca2ac30923a03bedfa3926eeaf97fb0b` |
| `rime_deployer.exe` | `3abb72b5bb56fcafcfe925d533ae5f832c68d5a0bc9952fd0eea0682fb1ab071` |
| `rime_dict_manager.exe` | `1c1eb1f84f98704161efbf3315a16e3456f5989efa56f340d7e9e3e5f8bf9e1b` |

## 发现并消除的迁移前问题

### 共享数据没有进入干净工作树

旧构建忽略了 `default.yaml`、基础方案、词典、`essay.txt` 和 `opencc/`。第一次
干净环境测试无法载入 `default:punctuator`，所有输入都被拒绝。补入与当前运行
版本相同的共享数据后，1.17.0 测试全部通过，因此这不是版本不兼容。

现行构建和 CI 直接使用已提交快照；缺少任一必需文件即失败。Weasel、Plum 和
`C:\dev\librime` 等机器本地兜底已从构建和运行路径移除。

### 运行时没有可靠版本门禁

Go 封装仍调用传统导出接口，不能依靠接口本身稳定取得运行时版本。现改为先验证
三件运行文件的 SHA-256，并检查锁文件中的版本与来源，再加载 DLL。哈希把实际
二进制与官方 1.17.0 精确绑定，避免不同 AI 或本机文件把运行时悄悄换回其他版本。

## 验证结果

- `go test ./...`：通过。
- `go test -race ./...`：使用 `C:\msys64\ucrt64\bin\gcc.exe` 通过。
- 真实 librime 集成测试：全部通过，耗时约 280 秒。
- `rime_deployer.exe`：外部构建及分页配置变更通过。
- `rime_dict_manager.exe`：转换后的用户词典快照恢复通过。
- 1.16.1 与 1.17.0 的七组固定候选快照：一致。
- Go 后端发布构建：通过；打包后的三件运行文件与锁文件哈希一致。

本机先前的竞态测试失败是 Codex 进程没有使用实际 MSYS2 GCC 路径，不是编译器
缺失或 librime 1.17.0 测试失败。

## 后续升级方法

升级 librime 时必须把 DLL、两个官方工具和锁文件作为一个原子变更：

1. 从同一官方发布包取得三个文件。
2. 更新版本、提交、插件提交和三个 SHA-256。
3. 运行 `tools/verify-rime-runtime.ps1`。
4. 运行普通 Go、竞态、真实 Rime、用户词典迁移及候选固定点测试。
5. 只有全部通过后才更新安装包。

不要将独立 `C:\dev\librime` 仓库重新加入运行时或构建兜底。

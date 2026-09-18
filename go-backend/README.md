# Yime Go 源码与 Rime/PIME 后端指南

本目录同时容纳 Rime/PIME 产品的 Go 后端框架，以及 YimeCore 产品的独立内核、Broker、运行维护工具等源码。按[双产品开发计划](../docs/project/YIME_DUAL_PRODUCT_DEVELOPMENT_PLAN_2026-09-05.md)，YimeCore 为主要功能开发方向，Rime/PIME 持续稳定维护；两者可各自单装或同时安装，运行、升级、卸载及可写数据必须互相独立，对方不存在时仍能工作。

两套产品的安装、卸载、重装均使用 [installer/simple](../installer/simple/README.md)，入口支持 YimeCore、Rime/PIME 或两套一起操作。已完成的实机范围与未测项见[维护验证记录](../installer/simple/VALIDATION.md)，新包交付以[当前交接](../installer/simple/HANDOFF.md)为准。

下文的 `server.exe`、PIME 配置、协议和构建指引仅适用于 **Rime/PIME 产品**。YimeCore 的源码构建、Broker、原生 TSF 和隔离验证使用[独立开发入口](../tools/yimecore/README.md)。`go-backend/` 是共同源码目录，不意味着两套产品共享已安装运行时或用户数据。

## 项目结构

```
go-backend/
├── pime/                 # PIME 核心库
│   ├── protocol.go     # 通信协议定义
│   ├── server.go       # 服务器实现
│   ├── service.go      # 文本服务接口
│   └── service_manager.go  # 服务管理器
├── input_methods/
│   └── yime/           # Yime 代码与数据；含 Rime 后端及独立 Core/Broker 等包
│       ├── engineapi/  # YimeCore 引擎接口
│       ├── yimecore/   # 独立索引、组句、学习与分段改选
│       └── yimebroker/ # 会话、传输、持久化与索引管理
├── cmd/               # 两套产品各自的工具、Broker/runtime 与离线验证命令
├── go.mod              # Go 模块定义
└── README.md           # 说明文档
```

## 快速开始（Rime/PIME）

### 1. 编译

完整产品构建应从仓库根目录执行：

```text
cmd /c build.bat
```

根脚本会串联 Win32/x64 原生组件、Go 后端和 PE 架构门禁。仅在专注开发 Go 后端时单独执行：

```text
cmd /c go-backend\build.bat
```

上述命令均从仓库根目录执行，只构建源码。`go-backend\build.bat` 会生成供根构建和制包入口消费的运行目录；主要文件如下：

```text
go-backend/build/
├── backends.go-backend.json
└── go-backend/
    ├── server.exe
    ├── tool-hub.exe
    ├── yime-trainer.exe
    ├── input-toolbar.exe
    ├── yime-layout-designer.exe
    ├── settings-tool.exe
    ├── diagnostics-tool.exe
    ├── lexicon-manager.exe
    ├── reverse-lookup.exe
    ├── system-lexicon-audit.exe
    ├── lexicon-promotion-scan.exe
    ├── blocklist-manager.exe
    └── input_methods/
```

### 2. 配置 PIME

`go-backend/build/backends.go-backend.json` 是单独构建 Go 后端时生成的中间配置片段；
制包入口会把最终配置写为产品包根目录的 `backends.json`，PIMELauncher 也只读取这个文件名。
开发或审查配置时以此结构为准；安装到系统请使用完整包，不手工拼装正在运行的 PIME 目录。

注意：这个仓库里的 `backends.json` 顶层是数组，不是 `{ "backends": [...] }`。

```json
[
  {
    "name": "go-backend",
    "command": "go-backend\\server.exe",
    "workingDir": "go-backend",
    "params": ""
  }
]
```

### 3. 输入法工厂与注册边界

Rime/PIME 产品包只注册 `input_methods/yime/ime.json`。目录扫描不会为未知名称提供默认输入法实现；新增产品输入法必须显式实现并注册工厂，不能回退到测试或演示服务。Windows COM/Profile 注册由所选产品的安装器执行。

## 测试入口

从仓库根目录运行共享 Go 回归；真实 Rime 和 race 各有独立入口：

```text
python -X utf8 tools/powershell/run_checked.py --script tools/test-go.ps1 --edition ps7
python -X utf8 tools/powershell/run_checked.py --script tools/test-real-rime.ps1 --edition ps7
python -X utf8 tools/powershell/run_checked.py --script tools/test-go-race.ps1 --edition ps7
```

按受影响范围选择测试，环境和安装态验证见[测试指南](../docs/YIME_TESTING_GUIDE.md)。YimeCore 的 Go 测试、隔离 TSF 契约和已安装宿主输入是不同证据层级；真实 Rime 回归也不能代替 YimeCore 独立验收。

服务器协议集成测试使用 `server_integration_test.go` 内的测试专用假服务。该 fixture 不进入生产二进制，也不在安装包中生成输入法目录。

## 协议说明（Rime/PIME）

### 通信方式

- 使用 stdin/stdout 进行通信
- 每行一条消息
- JSON 格式

### 请求格式

```
<client_id>|<JSON>
```

### 响应格式

```
PIME_MSG|<client_id>|<JSON>
```

### 消息类型

#### 初始化
```json
{
  "method": "init",
  "id": "client_guid",
  "isWindows8Above": true,
  "isMetroApp": false,
  "isUiLess": false,
  "isConsole": false
}
```

#### 按键处理
```json
{
  "method": "filterKeyDown",
  "keyCode": 65,
  "charCode": 97,
  "scanCode": 30
}
```

#### 响应
```json
{
  "success": true,
  "returnValue": 1,
  "compositionString": "a",
  "candidateList": ["啊", "阿", "吖"],
  "showCandidates": true
}
```

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

除另有说明外，Yime 新增 Go 后端代码采用 `LGPL-2.1-or-later`。其中继承的 PIME
协议代码保留原有版权和许可证。完整组件说明见仓库根目录的 `LICENSE.txt`、
`NOTICE.md` 与 `THIRD_PARTY_NOTICES.md`。

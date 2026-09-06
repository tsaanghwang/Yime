# Yime Go 源码与 Rime/PIME 后端指南

本目录同时容纳 Rime/PIME 产品的 Go 后端框架，以及 YimeCore 产品的独立内核、Broker、运行维护工具等源码。按[双产品开发计划](../docs/project/YIME_DUAL_PRODUCT_DEVELOPMENT_PLAN_2026-09-05.md)，YimeCore 为主要功能开发方向，Rime/PIME 持续稳定维护；两者可各自单装或同时安装，运行、升级、卸载及可写数据必须互相独立，对方不存在时仍能工作。

下文的 `server.exe`、PIME 配置、协议和构建指引仅适用于 **Rime/PIME 产品**，不能视为 YimeCore 的启动或安装流程。YimeCore 请使用[独立开发与维护入口](../tools/yimecore/README.md)。三种安装组合须分别验收；统一的“三选一”安装入口尚未实现。

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
├── go.mod              # Go 模块定义
└── README.md           # 说明文档
```

## 快速开始（Rime/PIME）

### 1. 编译

完整产品构建应从仓库根目录执行：

```powershell
cmd /c build.bat
```

根脚本会串联 Win32/x64 原生组件、Go 后端和 PE 架构门禁。仅在专注开发 Go 后端时单独执行：

```bash
cd go-backend
build.bat
```

`go-backend\build.bat` 会生成供根构建和安装器消费的运行目录：

```text
build/
├── backends.go-backend.json
└── go-backend/
    ├── server.exe
    ├── tool-hub.exe
    ├── input-toolbar.exe
    ├── yime-layout-designer.exe
    ├── settings-tool.exe
    ├── diagnostics-tool.exe
    ├── lexicon-manager.exe
    ├── reverse-lookup.exe
    ├── system-lexicon-audit.exe
    ├── blocklist-manager.exe
    └── input_methods/
```

### 2. 配置 PIME

在 PIME 根目录的 `backends.json` 中添加 Go 后端配置。

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

### 3. 注册输入法

产品包只注册 `input_methods/yime/ime.json`。目录扫描不会为未知名称提供默认输入法实现；新增产品输入法必须显式实现并注册工厂，不能回退到测试或演示服务。

## 测试输入法（Rime/PIME）

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

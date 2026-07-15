# PIME Go 后端

使用 Go 语言实现的 PIME 输入法后端框架。

## 项目结构

```
go-backend/
├── pime/                 # PIME 核心库
│   ├── protocol.go     # 通信协议定义
│   ├── server.go       # 服务器实现
│   ├── service.go      # 文本服务接口
│   └── service_manager.go  # 服务管理器
├── input_methods/
│   └── yime/           # 唯一产品输入法；Rime 后端与原生工具
├── go.mod              # Go 模块定义
└── README.md           # 说明文档
```

## 快速开始

### 1. 编译

```bash
cd go-backend
build.bat
```

`build.bat` 会生成可直接安装的运行目录：

```text
build/
├── backends.go-backend.json
└── go-backend/
    ├── server.exe
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

## 测试输入法

服务器协议集成测试使用 `server_integration_test.go` 内的测试专用假服务。该 fixture 不进入生产二进制，也不在安装包中生成输入法目录。

## 协议说明

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

LGPL-2.1 License

# libIME2 组件边界与提交门禁

`libIME2` 当前可以是 Git 子模块，后续也可以迁入主仓库成为普通目录。无论采用
哪种存放形式，其提交历史都必须保持可再次抽离。

## 常规修改

只要一个提交改动 `libIME2` 或 `libIME2/**`，该提交就必须：

1. 不同时修改主工程中的其他文件；
2. 在提交信息中加入非空尾注：

   ```text
   LibIME2-Change: 修复 TSF 候选定位
   ```

需要同时调整主工程调用方时，应拆成两个相邻提交：第一个只改 `libIME2`，
第二个只改主工程。这样以后可直接按目录提取组件历史。

## 边界迁移

子模块改为主仓库目录、重新抽成仓库，或恢复为子模块时，使用：

```text
LibIME2-Integration: vendor
LibIME2-Integration: extract
LibIME2-Integration: submodule
```

边界迁移提交除 `libIME2` 外，只能修改门禁列出的集成文件，例如
`.gitmodules`、顶层 CMake、CI、README 和本说明。其他功能修改必须另行提交。

## 执行位置

- `pre-commit`：拒绝暂存区中的跨组件混合修改；
- `commit-msg`：检查跟踪尾注；
- `pre-push`：逐个检查将要推送的提交；
- GitHub Actions：每次推送和 PR 再次检查，并上传
  `libime2-change-report-<commit>` 报告。

本地首次启用：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\enable-repository-hooks.ps1
```

CI 门禁属于现有 `native-build` 必需检查的一部分，因此门禁失败会直接阻止现有
受保护分支合入，不需要增加一个容易漏配的独立 required check。

# YimeCore 索引控制状态文件占用修复

影响产品：YimeCore Broker 索引控制观察器。CI 34491697334 的 go-race-msys2 在三模式回滚测试等待 `rollback-full` 时超时，随后临时索引清理报告文件占用；日志没有 DATA RACE 报告。

先补齐测试失败路径的引擎关闭与 watcher 退出等待，并报告其返回错误。本机普通模式重复测试复现：等待 `reject-shorthand` 超时，watcher 返回 `remove .../status.json: The process cannot access the file because it is being used by another process`。因此根因是 Windows 并发读取期间状态文件替换失败导致观察器退出，不是确认发生了 Go 内存数据竞争。

状态发布改用已有的原子替换原语，取消先删除旧状态再重命名的降级路径。仅 Windows access-denied、sharing-violation、lock-violation 错误重试，间隔 5 ms、预算 250 ms；其他错误立即返回。持续占用仍失败，最后一份完整旧状态保留。两个索引控制观察器共享此状态写入函数。测试自身的 2 秒等待门槛和 CI race 检查未放宽。

新增 Windows 原生读句柄持锁测试，分别验证释放后发布成功、持续占用失败且旧状态完整。验证结果：持锁与三模式回滚专项连续 20 轮通过；原失败测试 race 连续 50 轮通过；Broker 整包 race 通过。本机使用 MSYS2 UCRT64 GCC；未修改已安装二进制、注册、用户数据或 E3 性能门槛。新提交远端 CI 仍需独立确认。

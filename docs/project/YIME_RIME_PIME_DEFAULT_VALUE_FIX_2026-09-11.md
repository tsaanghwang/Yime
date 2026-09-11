# com-x64 安装失败：默认值枚举误判修复

影响产品：Rime/PIME 注册观察与所有权读取；YimeCore 保持保护对象。测试报告 `167c5906e` 中的安装失败已自动回滚，旧包不再重装。

## 已复现的缺陷

开发端只读观察现有 PIME COM 键的 Registry32/Registry64 两个视图：StdRegProv EnumValues 均返回 ReturnValue=0、sNames=null、Types=null；同一系统提供程序 GetStringValue 对空名称返回 ReturnValue=0、PIMETextService。EnumKey 返回 InprocServer32。没有注册、卸载或更改任何产品。

这符合 [Microsoft EnumValues 文档](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/regprov/enumvalues-method-in-class-stdregprov)：只有默认值的键可能返回空名称和类型数组。旧代码将这种返回值直接规范化为空集合，导致 com-x64 实际已有默认值时，观察仍为零个值，继而触发机器注册不完整断言。原模拟注册器总是显式列出空字符串名称，未覆盖真实提供程序的这种行为。

本地复现与测试端失败断言吻合，支持这是本轮安装的阻塞缺陷；现场失败时的完整快照未保留，仍须以新候选实机成功验证修复，不能称安装问题全部解决。

## 修复及验证

只在既存键、枚举没有值且预期包含默认 REG_SZ 时，通过系统提供程序的 [GetStringValue 空名称接口](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/regprov/getstringvalue-method-in-class-stdregprov)读取默认值。实际读取必须成功且数据为字符串，并继续核对内容、类型、子键和所属根。访问拒绝、默认值缺失或不支持的类型均拒绝，不补写注册、不把提供程序错误当成功。

额外的独立测试键验证发现 GetStringValue 也接受 REG_EXPAND_SZ，因此公共读取器明确返回类型歧义，不直接冒称 REG_SZ。候选注册适配器在已通过原生 Explorer/UAC 调用链准入的上下文中，补充只读的精确类型检查，要求 REG_SZ，并要求未展开的原生值与 StdRegProv 的值完全一致。系统提供程序失败时不会进行替代读取；补充结果只能增加拒绝条件，不能覆盖系统提供程序的失败或返回另一份值。其他调用者也不能把类型歧义当成 String 放行。

未预期默认值的空键保持原空集合语义；另为机器注册断言加入匹配数量、存在性、预期/实际值数和子键数，后续错误不再只剩 com-x64 标签。诊断不输出用户值内容。

- PS5/PS7 各 32 项注册回归通过，覆盖空枚举下默认值存在、缺失/错误类型、拒绝访问、null 数据、错误内容、可展开字符串以及原生/系统值不一致。系统调用和原生读取边界使用夹具，公共读取、观察和类型/值判断保持实际实现。
- PS5/PS7 各 22 项所有权检查通过；源基线 77 项通过。
- 修复后的实际只读 COM 观察在 Registry32/Registry64 均得到一个值、一个子键，reader=StdRegProv。生产安装保持不变。

旧 jobexit 包的自动回滚成功证据保持原样，不重写旧包内容。开发端制作独立的新候选及交接，等对应 CI 通过后，再在“计算机”执行一次新事务；此前失败事务不重放。新安装验收、宿主输入、重启和维护矩阵均未因本地测试而提升状态。

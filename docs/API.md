# YIME 项目 API 文档

## 目录
- Python 后端 API
  - YinjieEncoder
  - YinjieDecoder
  - Yinjie
- 前端/Node.js API
  - pinyinService.ts
  - pinyinModule.js
  - hanziModule.js
  - pinyinCodeModule.js
  - input-method.js

---

## Python 后端 API

### 1. `YinjieEncoder`
**位置**：yinjie_encoder.py
**功能**：音节编码，支持单个和批量音节编码，生成音节码表。

#### 主要方法
- `encode_single_yinjie(syllable: str) -> str`
  - 编码单个音节为码元字符串（4字符）。
  - **示例：**
    ```python
    encoder = YinjieEncoder()
    code = encoder.encode_single_yinjie('zhang1')
    print(code)  # 输出如：'A123'
    ```
- `encode_all_yinjie(output_subdir: str = "") -> Path`
  - 批量编码所有音节，结果保存为 JSON。
  - **示例：**
    ```python
    encoder = YinjieEncoder()
    path = encoder.encode_all_yinjie()
    print(f"已保存到: {path}")
    ```
- `generate_encoding_files() -> Path`
  - 兼容旧接口，等价于 `encode_all_yinjie()`。

---

### 2. `YinjieDecoder`
**位置**：yinjie_decoder.py
**功能**：音节码元解码，支持单个和批量解码，生成音元分类映射。

#### 主要方法
- `decode(pinyin: str) -> Yinjie`
  - 将拼音字符串解码为 `Yinjie` 实例。
  - **示例：**
    ```python
    decoder = YinjieDecoder()
    yinjie = decoder.decode('zhang1')
    print(yinjie.initial, yinjie.ascender, yinjie.peak, yinjie.descender)
    ```
- `decode_all() -> dict`
  - 批量解码所有拼音，返回 {pinyin: Yinjie} 字典。
  - **示例：**
    ```python
    decoder = YinjieDecoder()
    all_yinjie = decoder.decode_all()
    print(all_yinjie['zhang1'])
    ```
- `generate_phoneme_mapping() -> dict`
  - 生成音元分类映射（噪音/乐音）。
  - **示例：**
    ```python
    decoder = YinjieDecoder()
    mapping = decoder.generate_phoneme_mapping()
    print(mapping)
    ```
- `save_phoneme_dict(output_file: str)`
  - 保存音元分类到 JSON 文件。

---

### 3. `Yinjie`
**位置**：yinjie.py
**功能**：音节结构对象，支持音元分类、合并等。

#### 主要属性
- `initial`：首音（噪音）
- `ascender`：呼音（乐音）
- `peak`：主音（乐音）
- `descender`：末音（乐音）

#### 主要方法
- `classify_phonemes() -> (list, list)`
  - 返回（噪音音元列表, 乐音音元列表）
  - **示例：**
    ```python
    yinjie = Yinjie('h', 'a', 'i', 'n')
    noise, musical = yinjie.classify_phonemes()
    print('噪音:', noise, '乐音:', musical)
    ```
- `merge_duplicate_phonemes() -> Yinjie`
  - 合并连续相同音元，返回新实例

---

## 前端/Node.js API

### 1. `pinyinService.ts`
**位置**：src/services/pinyinService.ts
**功能**：前端拼音查词与用户词库管理。

#### 导出方法
- `getMatchedWordsByPinyin(pinyin: string): string[]`
  - 根据拼音查找匹配词语。
  - **示例：**
    ```typescript
    import { getMatchedWordsByPinyin } from './pinyinService';
    const words = getMatchedWordsByPinyin('zhang');
    console.log(words);
    ```
- `addUserWord(pinyin: string, word: string): void`
  - 向指定拼音添加用户词。
  - **示例：**
    ```typescript
    import { addUserWord } from './pinyinService';
    addUserWord('zhang', '张三');
    ```

---

### 2. `pinyinModule.js`
**功能**：Node.js 环境下拼音查词。

#### 导出方法
- `getMatchedWordsByPinyin(pinyin: string): string[]`
  - 返回拼音对应的词语数组。
  - **示例：**
    ```js
    const { getMatchedWordsByPinyin } = require('./pinyinModule');
    const words = getMatchedWordsByPinyin('zhang');
    console.log(words);
    ```

---

### 3. `hanziModule.js`
**功能**：Node.js 环境下汉字查找。

#### 导出方法
- `getMatchedHanzi(code: string): string[]`
  - 返回编码对应的汉字数组。
  - **示例：**
    ```js
    const { getMatchedHanzi } = require('./hanziModule');
    const hanzi = getMatchedHanzi('A123');
    console.log(hanzi);
    ```

---

### 4. `pinyinCodeModule.js`
**功能**：拼音到编码的查找。

#### 导出方法
- `getPinyinCode(pinyin: string): string | null`
  - 返回拼音对应的编码。
  - **示例：**
    ```js
    const { getPinyinCode } = require('./pinyinCodeModule');
    const code = getPinyinCode('zhang');
    console.log(code);
    ```

---

### 5. `input-method.js`
**功能**：输入法核心对象，支持词条增查。

#### 类与方法
- `InputMethod(name, version)`
  - 构造函数，初始化输入法对象。
  - **示例：**
    ```js
    const InputMethod = require('./input-method');
    const im = new InputMethod('YIME', '1.0');
    im.addWord('张三', 'A123');
    console.log(im.findWords('A123'));
    ```
- `addWord(word, code)`
  - 添加词条到码表。
- `findWords(code)`
  - 查找指定编码的所有词条。

---

## 说明
- 具体 JSON 结构（如 pinyinTable.json、hanziTable.json 等）请参考数据文件本身。
- 详细参数类型、异常说明、示例代码可根据需要进一步补充。
- 若需补充其它模块（如数据库、Web API、插件等），可继续细化。

class InputMethod {
  constructor(name, version) {
    this.name = name;
    this.version = version;
    this.dictionary = new Map(); // 使用 Map 存储码表
  }

  // 添加词条
  addWord(word, code) {
    if (!this.dictionary.has(code)) {
      this.dictionary.set(code, []);
    }
    this.dictionary.get(code).push(word);
  }

  // 查找词条
  findWords(code) {
    return this.dictionary.get(code) || [];
  }
}

module.exports = InputMethod;
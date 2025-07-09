// pinyinCodeModule.js
const pinyinCodeTable = require('./pinyinCodeTable.json');

// 获取编码
function getPinyinCode(pinyin) {
  return pinyinCodeTable[pinyin] || null;
}

module.exports = { getPinyinCode };
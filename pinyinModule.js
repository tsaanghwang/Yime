// pinyinModule.js
const pinyinTable = require('./pinyinTable.json');

// 获取匹配的词语
function getMatchedWordsByPinyin(pinyin) {
  return pinyinTable[pinyin] || [];
}

module.exports = { getMatchedWordsByPinyin };
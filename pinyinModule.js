// pinyinModule.js
const pinyinTable = require('./yime/pinyin_hanzi.json');

// 获取匹配的词语
function getMatchedWordsByPinyin(pinyin) {
  return pinyinTable[pinyin] || [];
}

module.exports = { getMatchedWordsByPinyin };

// pinyinModule.js
const pinyinCodeTable = require('./pinyinCodeTable.json');
const hanziTable = require('./hanziTable.json');

// 获取匹配的词语
function getMatchedWordsByPinyin(pinyin) {
  const code = pinyinCodeTable[pinyin];
  return code ? hanziTable[code] || [] : [];
}

module.exports = { getMatchedWordsByPinyin };

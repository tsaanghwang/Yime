// hanziModule.js
const hanziTable = require('./hanziTable.json');

// 获取匹配的汉字
function getMatchedHanzi(code) {
  return hanziTable[code] || [];
}

module.exports = { getMatchedHanzi };
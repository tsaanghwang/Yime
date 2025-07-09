// main.js
const readline = require('readline');
const { getMatchedWordsByPinyin } = require('./pinyinModule');

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

// 输入并选词
function inputAndSelectWords() {
  rl.question('请输入带调拼音（如 ni3hao3）：', (pinyin) => {
    const wordList = getMatchedWordsByPinyin(pinyin);
    if (wordList.length > 0) {
      console.log('匹配的词语：');
      wordList.forEach((word, index) => {
        console.log(`${index + 1}. ${word}`);
      });

      rl.question('请选择词语编号（输入 0 重新输入）：', (choice) => {
        const choiceIndex = parseInt(choice) - 1;
        if (choiceIndex >= 0 && choiceIndex < wordList.length) {
          console.log(`您选择的词语是：${wordList[choiceIndex]}`);
        } else if (choice === '0') {
          console.log('重新输入拼音。');
        } else {
          console.log('无效的选择！');
        }
        inputAndSelectWords(); // 继续监听下一次输入
      });
    } else {
      console.log('未找到匹配的词语！');
      inputAndSelectWords(); // 继续监听下一次输入
    }
  });
}

// 启动输入监听
inputAndSelectWords(); // 或者 inputAndSelectHanzi();
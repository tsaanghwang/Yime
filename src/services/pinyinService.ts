import pinyinData from '../../yime/pinyin_hanzi.json';

interface PinyinService {
  getMatchedWordsByPinyin: (pinyin: string) => string[];
  addUserWord: (pinyin: string, word: string) => void;
}

const service: PinyinService = {
  getMatchedWordsByPinyin: (pinyin) => {
    return pinyinData[pinyin as keyof typeof pinyinData] || [];
  },

  addUserWord: (pinyin, word) => {
    if (!pinyinData[pinyin as keyof typeof pinyinData]) {
      pinyinData[pinyin as keyof typeof pinyinData] = [];
    }
    pinyinData[pinyin as keyof typeof pinyinData].unshift(word);
  }
};

export const { getMatchedWordsByPinyin, addUserWord } = service;

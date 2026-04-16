import pinyinCodeTable from '../../pinyinCodeTable.json';
import hanziTable from '../../hanziTable.json';

interface PinyinService {
  getMatchedWordsByPinyin: (pinyin: string) => string[];
  addUserWord: (pinyin: string, word: string) => void;
}

const userWords: Record<string, string[]> = {};

const service: PinyinService = {
  getMatchedWordsByPinyin: (pinyin) => {
    const customWords = userWords[pinyin] || [];
    const code = pinyinCodeTable[pinyin as keyof typeof pinyinCodeTable];
    const builtInWords = code ? hanziTable[code as keyof typeof hanziTable] || [] : [];

    return [...customWords, ...builtInWords];
  },

  addUserWord: (pinyin, word) => {
    if (!userWords[pinyin]) {
      userWords[pinyin] = [];
    }

    userWords[pinyin].unshift(word);
  }
};

export const { getMatchedWordsByPinyin, addUserWord } = service;

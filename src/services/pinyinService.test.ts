// src/services/pinyinService.test.ts
import { getMatchedWordsByPinyin, addUserWord } from './pinyinService';

jest.mock('../../pinyinCodeTable.json', () => ({
  zhong: 'ZHONG_CODE',
  guo: 'GUO_CODE',
  ren: 'REN_CODE',
}));

jest.mock('../../hanziTable.json', () => ({
  ZHONG_CODE: ['中', '重', '种'],
  GUO_CODE: ['国', '过'],
  REN_CODE: ['人', '认'],
}));

describe('PinyinService', () => {
  beforeEach(() => {
    // 重置 mock
    jest.clearAllMocks();
  });

  test('getMatchedWordsByPinyin returns words for existing pinyin', () => {
    const result = getMatchedWordsByPinyin('zhong');
    expect(result).toEqual(['中', '重', '种']);
  });

  test('getMatchedWordsByPinyin returns empty array for non-existent pinyin', () => {
    const result = getMatchedWordsByPinyin('nonexistent');
    expect(result).toEqual([]);
  });

  test('getMatchedWordsByPinyin handles empty string', () => {
    const result = getMatchedWordsByPinyin('');
    expect(result).toEqual([]);
  });

  test('addUserWord adds word to existing pinyin', () => {
    addUserWord('zhong', '众');
    const result = getMatchedWordsByPinyin('zhong');
    expect(result).toContain('众');
    expect(result[0]).toBe('众'); // 应该在开头
    expect(result.slice(1)).toEqual(['中', '重', '种']);
  });

  test('addUserWord creates new pinyin entry if not exists', () => {
    addUserWord('newpinyin', '新词');
    const result = getMatchedWordsByPinyin('newpinyin');
    expect(result).toContain('新词');
  });
});

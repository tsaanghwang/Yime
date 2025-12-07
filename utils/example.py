import json
from collections import defaultdict

class PositionAwareCharacterTable:
    def __init__(self):
        # 初始化数据结构
        self.char_stats = defaultdict(lambda: defaultdict(int))
        self.transition_matrix = defaultdict(lambda: defaultdict(lambda: defaultdict(int)))
        self.cooccurrence = defaultdict(lambda: defaultdict(lambda: defaultdict(int)))

        # 位置类型定义
        self.position_types = {
            'SOLO': 0,    # 独立成词
            'BEGIN': 1,   # 词首
            'MIDDLE': 2,  # 词中
            'END': 3      # 词尾
        }

        # 反向映射
        self.position_names = {v: k for k, v in self.position_types.items()}

        # 总词数统计
        self.total_words = 0

    def analyze_word(self, word):
        """分析单个词语，更新统计信息"""
        if not word:
            return

        self.total_words += 1
        chars = list(word)
        length = len(chars)

        # 处理单字词
        if length == 1:
            char = chars[0]
            self.char_stats[char]['SOLO'] += 1
            return

        # 处理多字词
        for i, char in enumerate(chars):
            # 确定位置类型
            if i == 0:
                pos_type = 'BEGIN'
            elif i == length - 1:
                pos_type = 'END'
            else:
                pos_type = 'MIDDLE'

            # 更新字符统计
            self.char_stats[char][pos_type] += 1

            # 如果是词首，没有前驱字符
            if i == 0:
                continue

            # 更新转移矩阵和共现统计
            prev_char = chars[i-1]
            prev_pos = 'BEGIN' if i-1 == 0 else 'MIDDLE' if i-1 < length -1 else 'END'

            # 转移矩阵: 前一个位置类型 -> 当前位置类型 -> 字符计数
            self.transition_matrix[prev_pos][pos_type][char] += 1

            # 共现统计: 前一个字符 -> 当前字符 -> 位置类型计数
            self.cooccurrence[prev_char][char][pos_type] += 1

    def analyze_corpus(self, corpus):
        """分析语料库"""
        for word in corpus:
            self.analyze_word(word)

    def get_position_prob(self, char, position):
        """获取字符在特定位置出现的概率"""
        total = sum(self.char_stats[char].values())
        if total == 0:
            return 0.0
        return self.char_stats[char].get(position, 0) / total

    def get_transition_prob(self, prev_pos, current_pos, char):
        """获取从prev_pos位置转移到current_pos位置生成特定字符的概率"""
        total = sum(self.transition_matrix[prev_pos][current_pos].values())
        if total == 0:
            return 0.0
        return self.transition_matrix[prev_pos][current_pos].get(char, 0) / total

    def get_cooccurrence_prob(self, prev_char, current_char, position):
        """获取前一个字符后接当前字符在特定位置的概率"""
        total = sum(self.cooccurrence[prev_char][current_char].values())
        if total == 0:
            return 0.0
        return self.cooccurrence[prev_char][current_char].get(position, 0) / total

    def predict_next_char(self, prev_char, prev_pos):
        """预测下一个最可能的字符及其位置"""
        if prev_char not in self.cooccurrence:
            return None, None

        max_prob = 0
        best_char = None
        best_pos = None

        for current_char in self.cooccurrence[prev_char]:
            for pos_type in ['BEGIN', 'MIDDLE', 'END']:
                prob = self.get_cooccurrence_prob(prev_char, current_char, pos_type)
                if prob > max_prob:
                    max_prob = prob
                    best_char = current_char
                    best_pos = pos_type

        return best_char, best_pos

    def predict_prev_char(self, current_char, current_pos):
        """逆向预测前一个最可能的字符及其位置"""
        # 这里简化实现，实际需要更复杂的逆向统计
        max_prob = 0
        best_char = None
        best_pos = None

        for prev_char in self.cooccurrence:
            if current_char in self.cooccurrence[prev_char]:
                for pos_type in ['BEGIN', 'MIDDLE', 'END']:
                    prob = self.get_cooccurrence_prob(prev_char, current_char, current_pos)
                    if prob > max_prob:
                        max_prob = prob
                        best_char = prev_char
                        best_pos = pos_type

        return best_char, best_pos

    def save(self, filename):
        """保存统计信息到文件"""
        data = {
            'char_stats': self.char_stats,
            'transition_matrix': self.transition_matrix,
            'cooccurrence': self.cooccurrence,
            'total_words': self.total_words
        }
        with open(filename, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    def load(self, filename):
        """从文件加载统计信息"""
        with open(filename, 'r', encoding='utf-8') as f:
            data = json.load(f)

        self.char_stats = defaultdict(lambda: defaultdict(int), data['char_stats'])
        self.transition_matrix = defaultdict(
            lambda: defaultdict(lambda: defaultdict(int)),
            data['transition_matrix']
        )
        self.cooccurrence = defaultdict(
            lambda: defaultdict(lambda: defaultdict(int)),
            data['cooccurrence']
        )
        self.total_words = data['total_words']

if __name__ == "__main__":
    # 示例语料库
    corpus = [
        "中国", "人民", "银行", "中国人民银行",
        "北京", "大学", "北京大学", "清华", "清华大学",
        "电脑", "手机", "电话", "电视"
    ]

    # 创建并分析字符表
    pct = PositionAwareCharacterTable()
    pct.analyze_corpus(corpus)

    # 保存字符表
    pct.save("character_table.json")

    # 加载字符表
    new_pct = PositionAwareCharacterTable()
    new_pct.load("character_table.json")

    # 测试预测功能
    print("正向预测:")
    print("'中'后面最可能的字符:", new_pct.predict_next_char('中', 'BEGIN'))
    print("'国'后面最可能的字符:", new_pct.predict_next_char('国', 'END'))

    print("\n逆向预测:")
    print("'民'前面最可能的字符:", new_pct.predict_prev_char('民', 'MIDDLE'))
    print("'学'前面最可能的字符:", new_pct.predict_prev_char('学', 'END'))

    # 查看字符位置分布
    print("\n字符'大'的位置分布:")
    for pos, count in new_pct.char_stats['大'].items():
        print(f"{pos}: {count}次 (概率: {new_pct.get_position_prob('大', pos):.2f})")

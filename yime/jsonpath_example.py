data = {
    "store": {
        "book": [
            {
                "category": "reference",
                "author": "Nigel Rees",
                "title": "Sayings of the Century",
                "price": 8.95
            },
            {
                "category": "fiction",
                "author": "Evelyn Waugh",
                "title": "Sword of Honour",
                "price": 12.99
            },
            {
                "category": "fiction",
                "author": "Herman Melville",
                "title": "Moby Dick",
                "isbn": "0-553-21311-3",
                "price": 8.99
            },
            {
                "category": "fiction",
                "author": "J. R. R. Tolkien",
                "title": "The Lord of the Rings",
                "isbn": "0-395-19395-8",
                "price": 22.99
            }
        ],
        "bicycle": {
            "color": "red",
            "price": 19.95
        }
    }
}

from jsonpath_ng import parse

# 查找所有书籍的标题
jsonpath_expr = parse("$.store.book[*].title")
titles = [match.value for match in jsonpath_expr.find(data)]
print(titles)
# 输出: ['Sayings of the Century', 'Sword of Honour', 'Moby Dick', 'The Lord of the Rings']

# 查找商店中所有价格
jsonpath_expr = parse("$.store..price")
prices = [match.value for match in jsonpath_expr.find(data)]
print(prices)
# 输出: [8.95, 12.99, 8.99, 22.99, 19.95]

# 查找价格低于10的书籍
jsonpath_expr = parse("$.store.book[?(@.price < 10)].title")
cheap_books = [match.value for match in jsonpath_expr.find(data)]
print(cheap_books)
# 输出: ['Sayings of the Century', 'Moby Dick']

# 查找特定类别的书籍
jsonpath_expr = parse("$.store.book[?(@.category == 'fiction')].title")
fiction_books = [match.value for match in jsonpath_expr.find(data)]
print(fiction_books)
# 输出: ['Sword of Honour', 'Moby Dick', 'The Lord of the Rings']

# 查找第一本书
jsonpath_expr = parse("$.store.book[0].title")
first_book = [match.value for match in jsonpath_expr.find(data)]
print(first_book)
# 输出: ['Sayings of the Century']

# 查找前两本书
jsonpath_expr = parse("$.store.book[0:2].title")
first_two_books = [match.value for match in jsonpath_expr.find(data)]
print(first_two_books)
# 输出: ['Sayings of the Century', 'Sword of Honour']

# 递归查找所有作者
jsonpath_expr = parse("$..author")
authors = [match.value for match in jsonpath_expr.find(data)]
print(authors)
# 输出: ['Nigel Rees', 'Evelyn Waugh', 'Herman Melville', 'J. R. R. Tolkien']

# 同时获取标题和作者
jsonpath_expr = parse("$.store.book[*].['title','author']")
for match in jsonpath_expr.find(data):
    print(match.value)
# 输出:
# ['Sayings of the Century', 'Nigel Rees']
# ['Sword of Honour', 'Evelyn Waugh']
# ['Moby Dick', 'Herman Melville']
# ['The Lord of the Rings', 'J. R. R. Tolkien']

# 查找有ISBN的书籍
jsonpath_expr = parse("$.store.book[?(@.isbn)].title")
books_with_isbn = [match.value for match in jsonpath_expr.find(data)]
print(books_with_isbn)
# 输出: ['Moby Dick', 'The Lord of the Rings']


# 使用长度函数
jsonpath_expr = parse("$.store.book.length()")
book_count = [match.value for match in jsonpath_expr.find(data)]
print(book_count)  # 输出: [4]

# 使用字符串函数
jsonpath_expr = parse("$.store.book[*].title.substring(0, 5)")
title_prefixes = [match.value for match in jsonpath_expr.find(data)]
print(title_prefixes)
# 输出: ['Sayin', 'Sword', 'Moby ', 'The L']



data = {
    "store": {
        "book": [
            {"title": "Book1", "price": 10},
            {"title": "Book2", "price": 20}
        ]
    }
}

# 严格匹配 $.store.book
jsonpath_expr = parse("$.store.book")
matches = [match.value for match in jsonpath_expr.find(data)]
print(matches)  # 输出: [[{'title': 'Book1', 'price': 10}, {'title': 'Book2', 'price': 20}]]


# 递归搜索所有 price
jsonpath_expr = parse("$.store..price")
prices = [match.value for match in jsonpath_expr.find(data)]
print(prices)  # 输出: [10, 20, 19.95]（假设 bicycle 的 price 是 19.95）


# 从键盘上输入键位 (keystroke) 或键位序列 (keystroke sequence)(暂定分大小写)
# 在可编辑输入框下方一行：
# 1. 显示与输入键位对应的用专用区代码点来编码的音元(yinyuan)或音元序列 (yinyuan sequence)  输入键位 (keystroke) 或键位序列 (keystroke sequence)
# 2. 同时显示与音元 (yinyuan) 或音元序列 (yinyuan sequence) 对应的标准拼音
# 在可编辑输入框下方另起一行：
# 显示音元(yinyuan)或音元序列(yinyuan sequence)对应的可翻页的候选汉字列表
# 例如：输入键位序列 'Baaa'->显示音元序列"􀀀􀀩􀀩􀀩"->显示"bā"
# ->显示候选汉字列表"巴、吧、八、..."

class OrderedSet:
    def __init__(self):
        self.set = set()
        self.list = []

    def add(self, value):
        if value not in self.set:
            self.set.add(value)
            self.list.append(value)

    def remove(self, value):
        if value in self.set:
            self.set.remove(value)
            self.list.remove(value)

    def __iter__(self):
        return iter(self.list)

# 使用
ordered_set = OrderedSet()
ordered_set.add(3)
ordered_set.add(1)
ordered_set.add(2)
print(list(ordered_set))  # 输出: [3, 1, 2]（按插入顺序）

from collections import OrderedDict

od = OrderedDict()
od['a'] = 1
od['b'] = 2
od['c'] = 3

print(list(od.keys()))  # 输出: ['a', 'b', 'c']（插入顺序）
od.move_to_end('a')     # 将键'a'移到末尾
print(list(od.keys()))  # 输出: ['b', 'c', 'a']
print(list(od.values()))        # 输出: [2, 3, 1]
print(list(od.items()))        # 输出:[('b', 2), ('c', 3), ('a', 1)]
print(set(od.items()))        # 输出:[('b', 2), ('c', 3), ('a', 1)]
print(od.get('a'))        # 输出: 1


import json

class User:
    def __init__(self, name, age):
        self.name = name
        self.age = age

    def to_dict(self):
        return {"name": self.name, "age": self.age}

user = User("王五", 25)

# 方法1: 使用自定义序列化函数
def user_handler(obj):
    if hasattr(obj, 'to_dict'):
        return obj.to_dict()
    raise TypeError("对象无法序列化")

json_string = json.dumps(user, default=user_handler, ensure_ascii=False)
print(json_string)

# 方法2: 先转换为字典
user_dict = user.to_dict()
json_string = json.dumps(user_dict, ensure_ascii=False)
print(json_string)


from bintrees import AVLTree

tree = AVLTree()
tree.insert(3, "C")
tree.insert(1, "A")
tree.insert(2, "B")

# 按顺序遍历
for key, value in tree.iter_items():
    print(key, value)  # 输出: 1 value1, 2 value2, 3 value3

# 范围查询
print(list(tree.iter_items(1, 4)))  # 输出: [(1, 'value1'), (2, 'value2'), (3, 'value3')]


class AVLNode:
    def __init__(self, key):
        self.key = key
        self.left = None
        self.right = None
        self.height = 1

class AVLTree:
    def insert(self, root, key):
        # 标准AVL插入逻辑（略）
        pass

    def inorder(self, root):
        # 中序遍历（按顺序输出）
        if root:
            self.inorder(root.left)
            print(root.key)
            self.inorder(root.right)

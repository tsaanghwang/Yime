my_dict = {"name": "Alice", "age": 30}

# 读取存在的键
name = my_dict.get("name")
print(name)  # 输出: Alice

# 读取不存在的键（返回 None 或指定默认值）
country = my_dict.get("country")  # 返回 None
print(country)  # 输出: None

country = my_dict.get("country", "USA")  # 指定默认值
print(country)  # 输出: USA
# 示例代码：使用 JSON Reference Navigator 解析引用
import jsonref

json_data = {
    "definitions": {
        "address": {
            "street": "Main Street", 
            "city": "Anytown"
        }
    },
    "home": {"$ref": "#/definitions/address"},
    "work": {"$ref": "#/definitions/address"}
}

# 使用正确的 replace_refs() 方法替代 resolve_references()
resolved_data = jsonref.replace_refs(json_data)
print(resolved_data)
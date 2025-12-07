from pathlib import Path
import sys, json

def hexdump(b, n=32):
    return " ".join(f"{x:02x}" for x in b[:n])

def try_load_text(text):
    try:
        return json.loads(text)
    except Exception as e:
        raise

def main():
    if len(sys.argv) < 2:
        print("Usage: python validate_json.py <path/to/code_pinyin.json>")
        return
    p = Path(sys.argv[1])
    if not p.exists():
        print("文件不存在:", p)
        return
    raw = p.read_bytes()
    print("大小:", raw.__len__(), "bytes")
    print("前 32 字节 (hex):", hexdump(raw, 32))

    # 尝试直接解析（假设 UTF-8）
    try:
        doc = json.loads(raw.decode("utf-8"))
        print("直接解析成功：JSON 合法")
        return
    except Exception as e:
        print("直接解析失败:", e)

    # 尝试去掉 UTF-8 BOM
    bom = b'\xef\xbb\xbf'
    if raw.startswith(bom):
        try:
            doc = json.loads(raw[len(bom):].decode("utf-8"))
            out = p.with_name(p.stem + ".repaired.json")
            out.write_text(json.dumps(doc, ensure_ascii=False, indent=2), encoding="utf-8")
            print("解析成功（去 BOM），已写出修复文件：", out)
            return
        except Exception as e:
            print("去 BOM 后仍解析失败:", e)

    # 尝试移除前导非 JSON 字符（找到第一个 { 或 [）
    text = raw.decode("utf-8", errors="replace")
    first_idx = min((text.find("{") if "{" in text else len(text)),
                    (text.find("[") if "[" in text else len(text)))
    if first_idx < len(text):
        candidate = text[first_idx:]
        try:
            doc = json.loads(candidate)
            out = p.with_name(p.stem + ".repaired.json")
            out.write_text(json.dumps(doc, ensure_ascii=False, indent=2), encoding="utf-8")
            print("解析成功（移除前导垃圾），已写出修复文件：", out)
            return
        except Exception as e:
            print("移除前导垃圾后仍解析失败:", e)

    print("自动修复失败。请打开文件检查是否含注释或不是 JSON。可粘出前 200 字符我帮看。")

if __name__ == "__main__":
    main()

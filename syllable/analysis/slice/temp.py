"""
修改84-85行：
    for final in triple_quality:
        print(f"   '{final}' - 长度: {len(final.replace('ng', 'N').replace('io', 'y'))}")
改成：
    当韵母长度==2 and 第二个单位（字符）是"i"/"n"时，输出信息："脱落韵腹[ᵊ]的三质韵母"
    当韵母长度==2 and 第二个单位（字符或字符组合）是"u"/"ng"时，输出信息："脱落韵腹[𐞑]的三质韵母"
   """

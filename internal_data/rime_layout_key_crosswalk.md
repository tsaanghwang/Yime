# Rime Layout Key Crosswalk

This table is for manual checking of the current Yime-to-Rime export path.

- Source layout: `internal_data/manual_key_layout.json`
- Source symbol map: `internal_data/key_to_symbol.json`
- Rime export mapping: `yime.utils.rime_export.load_runtime_symbol_to_layout_key()`
- Current Rime code form: `layout-key`

| yinyuan_id | Yime 正式键位 | Rime 输入键位 | 码元字符 | 码位 |
| --- | --- | --- | --- | --- |
| N01 | `q` | `q` | 􀀀 | `U+100000` |
| N02 | `p` | `p` | 􀀁 | `U+100001` |
| N03 | `[` | `[` | 􀀂 | `U+100002` |
| N04 | `h` | `h` | 􀀃 | `U+100003` |
| N05 | `w` | `w` | 􀀄 | `U+100004` |
| N06 | `.` | `.` | 􀀅 | `U+100005` |
| N07 | `b` | `b` | 􀀆 | `U+100006` |
| N08 | `y` | `y` | 􀀇 | `U+100007` |
| N09 | `]` | `]` | 􀀈 | `U+100008` |
| N10 | `'` | `'` | 􀀉 | `U+100009` |
| N11 | `n` | `n` | 􀀊 | `U+10000A` |
| N12 | `H` | `H` | 􀀋 | `U+10000B` |
| N13 | `6` | `6` | 􀀌 | `U+10000C` |
| N14 | `5` | `5` | 􀀍 | `U+10000D` |
| N15 | `4` | `4` | 􀀎 | `U+10000E` |
| N16 | `7` | `7` | 􀀏 | `U+10000F` |
| N17 | `8` | `8` | 􀀐 | `U+100010` |
| N18 | `9` | `9` | 􀀑 | `U+100011` |
| N19 | `0` | `0` | 􀀒 | `U+100012` |
| N20 | `3` | `3` | 􀀓 | `U+100013` |
| N21 | `2` | `2` | 􀀔 | `U+100014` |
| N22 | `1` | `1` | 􀀕 | `U+100015` |
| N23 | `$` | `$` | 􀀖 | `U+100016` |
| N24 | `%` | `%` | 􀀗 | `U+100017` |
| M01 | `u` | `u` | 􀀠 | `U+100020` |
| M02 | `;` | `;` | 􀀡 | `U+100021` |
| M03 | `o` | `o` | 􀀢 | `U+100022` |
| M04 | `v` | `v` | 􀀣 | `U+100023` |
| M05 | `g` | `g` | 􀀤 | `U+100024` |
| M06 | `x` | `x` | 􀀥 | `U+100025` |
| M07 | `/` | `/` | 􀀦 | `U+100026` |
| M08 | `z` | `z` | 􀀧 | `U+100027` |
| M09 | `,` | `,` | 􀀨 | `U+100028` |
| M10 | `f` | `f` | 􀀩 | `U+100029` |
| M11 | `d` | `d` | 􀀪 | `U+10002A` |
| M12 | `s` | `s` | 􀀫 | `U+10002B` |
| M13 | `j` | `j` | 􀀬 | `U+10002C` |
| M14 | `k` | `k` | 􀀭 | `U+10002D` |
| M15 | `l` | `l` | 􀀮 | `U+10002E` |
| M16 | `t` | `t` | 􀀯 | `U+10002F` |
| M17 | `r` | `r` | 􀀰 | `U+100030` |
| M18 | `e` | `e` | 􀀱 | `U+100031` |
| M19 | `J` | `J` | 􀀲 | `U+100032` |
| M20 | `K` | `K` | 􀀳 | `U+100033` |
| M21 | `L` | `L` | 􀀴 | `U+100034` |
| M22 | `A` | `A` | 􀀵 | `U+100035` |
| M23 | `S` | `S` | 􀀶 | `U+100036` |
| M24 | `D` | `D` | 􀀷 | `U+100037` |
| M25 | `!` | `!` | 􀀸 | `U+100038` |
| M26 | `@` | `@` | 􀀹 | `U+100039` |
| M27 | `#` | `#` | 􀀺 | `U+10003A` |
| M28 | `a` | `a` | 􀀻 | `U+10003B` |
| M29 | `N` | `N` | 􀀼 | `U+10003C` |
| M30 | `m` | `m` | 􀀽 | `U+10003D` |
| M31 | `i` | `i` | 􀀾 | `U+10003E` |
| M32 | `M` | `M` | 􀀿 | `U+10003F` |
| M33 | `c` | `c` | 􀁀 | `U+100040` |

All Yinyuan IDs now use the base or shift layer. The five formerly AltGr-only
rows directly use the same `!`, `@`, `#`, `$`, and `%` layout keys as the
Windows Yime build.

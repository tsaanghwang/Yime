# Runtime Tuning Scan

- generated_at: `2026-05-08T11:53:04.721735Z`
- combinations: `1`
- page_size: `5`
- high_collision_bucket_limit: `20`
- global baseline modern_common: top1 `15.09%`, first-page `44.38%`
- local baseline modern_common: top1 `3.70%`, first-page `13.17%`
- current_default_tuning: `cw=0.00, uw=0.00, scale=0.25, share>=0.995, count>=2, evidence>=0.00`

## Recommendation Summary

- pareto_source: `local_non_regression`
- global_non_regression_count: `1`
- local_non_regression_count: `1`
- local_improvement_count: `0`
- strict_usable_count: `1`
- tolerant_usable_count: `1`
- tolerance_band: `global_first_page>=-0.000000, global_top1>=-0.000000, local_first_page>=-0.000000, local_top1>=-0.000000`
- best_global_first_page: `cw=0.00, scale=0.25, share>=0.995, count>=2, evidence>=0.00, first-page=44.38%`
- best_local_first_page: `cw=0.00, scale=0.25, share>=0.995, count>=2, evidence>=0.00, local_first-page=13.17%`

## Tolerance-Usable Combinations

| rank | cw | uw | scale | share | count | evidence | Δglobal top1 | Δglobal first-page | Δlocal top1 | Δlocal first-page |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.00 | -0.00 | 0.25 | 0.995 | 2 | 0.00 | 0.00% | 0.00% | 0.00% | 0.00% |

## Strictly Usable Combinations

| rank | cw | uw | scale | share | count | evidence | global top1 | global first-page | local top1 | local first-page |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.00 | -0.00 | 0.25 | 0.995 | 2 | 0.00 | 15.09% | 44.38% | 3.70% | 13.17% |

## Pareto Frontier

| rank | cw | uw | scale | share | count | evidence | global first-page | Δglobal first-page | local first-page | Δlocal first-page |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.00 | -0.00 | 0.25 | 0.995 | 2 | 0.00 | 44.38% | 0.00% | 13.17% | 0.00% |

## Top Results

| rank | cw | uw | scale | share | count | evidence | enabled | global top1 | global first-page | Δglobal first-page | local top1 | local first-page | Δlocal first-page |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.00 | -0.00 | 0.25 | 0.995 | 2 | 0.00 | 5833 | 15.09% | 44.38% | 0.00% | 3.70% | 13.17% | 0.00% |

## High Collision Buckets

| pinyin_tone | yime_code | candidates | demand_weight_sum | collision_demand_score | current_runtime_top_texts |
| --- | --- | ---: | ---: | ---: | --- |
| yi4 | 􀀖􀀠􀀡􀀢 | 513 | 72416 | 37149408 | 一、食、意、亦、易、义、议、亿 |
| yu4 | 􀀖􀀦􀀧􀀨 | 330 | 57373 | 18933090 | 与、玉、遇、雨、欲、育、愈、王 |
| xi1 | 􀀕􀀠􀀠􀀠 | 335 | 50873 | 17042455 | 西、吸、息、溪、悉、稀、茜、栖 |
| li4 | 􀀆􀀠􀀡􀀢 | 364 | 44503 | 16199092 | 力、立、利、例、丽、粒、哩、历 |
| bi4 | 􀀀􀀠􀀡􀀢 | 310 | 49708 | 15409480 | 佛、必、服、秘、臂、被、闭、毕 |
| zhi4 | 􀀏􀀲􀀳􀀴 | 326 | 42294 | 13787844 | 至、制、知、治、质、致、志、置 |
| ji4 | 􀀓􀀠􀀡􀀢 | 260 | 42620 | 11081200 | 济、既、计、记、系、其、齐、季 |
| ji1 | 􀀓􀀠􀀠􀀠 | 217 | 41550 | 9016350 | 几、机、期、积、鸡、奇、其、击 |
| shi4 | 􀀑􀀲􀀳􀀴 | 198 | 44372 | 8785656 | 似、是、事、市、式、氏、视、世 |
| yu2 | 􀀖􀀨􀀧􀀦 | 234 | 37439 | 8760726 | 与、余、鱼、予、逾、俞、渝、于 |
| jue2 | 􀀓􀀨􀀰􀀯 | 251 | 34600 | 8684600 | 觉、嚼、角、绝、决、乙、掘、倔 |
| qi2 | 􀀔􀀢􀀡􀀠 | 220 | 38403 | 8448660 | 其、齐、奇、骑、旗、棋、七、祁 |
| fu2 | 􀀂􀀥􀀤􀀣 | 231 | 35671 | 8240001 | 服、佛、还、幅、福、夫、扶、浮 |
| yi2 | 􀀖􀀢􀀡􀀠 | 224 | 34817 | 7799008 | 一、疑、遗、台、宜、移、姨、蛇 |
| bo2 | 􀀀􀀮􀀭􀀬 | 202 | 35032 | 7076464 | 薄、柏、佛、伯、服、暴、泊、跑 |
| ji2 | 􀀓􀀢􀀡􀀠 | 220 | 30385 | 6684700 | 即、及、急、集、级、极、吉、疾 |
| e4 | 􀀋􀀬􀀭􀀮 | 207 | 28414 | 5881698 | 恶、啊、哦、饿、喔、呃、歹、厄 |
| yan4 | 􀀖􀀩􀀪􀀽 | 179 | 32671 | 5848109 | 咽、燕、验、但、厌、宴、艳、言 |
| ling2 | 􀀆􀀢􀀭􀀾 | 208 | 26632 | 5539456 | 令、零、灵、陵、棱、铃、冷、龄 |
| jie2 | 􀀓􀀢􀀰􀀯 | 211 | 26189 | 5525879 | 结、节、截、契、劫、洁、概、杰 |

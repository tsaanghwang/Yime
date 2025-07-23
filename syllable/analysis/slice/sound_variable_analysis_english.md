# Yinyuan Analysis Process

## Description of the Yinyuan Analysis Process

**Start**

- Begin the yinyuan (phonetic variable) analysis

**音节 Analysis**

- Each 音节 (syllable) is analyzed into a yinyuan sequence

**首音 and 干音**

- A syllable consists of a shouyin (initial) and a ganyin (final with tone  or divisional rhyme)
  - **首音**
    - Composed of a shoudiao and a shouzhi
      - The shoudiao is the tonal segment connected to the shouzhi
      - The shouyin is represented by unpitched sound
  - **干音**
    - Composed of a ganyin tone and a final
      - The ganyin tone is the tonal segment connected to the final
      - The ganyin is represented by sequences of pitched sound
  - **Yinyuan**
    - The yinyuan is the set of unpitched and pitched sounds that make up all syllables

**干音 Classification**

- 干音 is divided into four types:
  - **三质干音**
    - Composed of a ganyin tone and a tri-quality final
      - The tri-quality final consists of a medial, nucleus, and coda
      - The ganyin tone is divided into second tone, main tone, and coda tone
      - Onset tone and medial form the onset sound
      - Main tone and nucleus form the main sound
      - Modiao and coda form the coda sound
  - **前长干音**
    - Composed of a ganyin tone and a front long final
    - The front long final consists of a nucleus and coda
    - The ganyin tone is divided into medial tone and coda tone
      - Hudiao and nucleus form the medial sound
      - Hudiao is further divided into second tone and main tone
      - The nucleus is divided into onset quality and main quality (anterior and posterior parts of the nucleus)
      - Onset tone and onset quality form the onset sound
      - Main tone and main quality form the main sound
      - Modiao and coda form the coda sound
  - **后长干音**
    - Composed of a ganyin tone and a back long final
    - The back long final consists of a medial and a nucleus
    - The ganyin tone is divided into second tone and rhyme tone
      - Onset tone and medial form the onset sound
      - Rhyme tone and nucleus form the rhyme sound
      - Rhyme tone is further divided into main tone and coda tone
      - The nucleus is divided into main quality and coda quality (anterior and posterior parts of the nucleus)
      - Main tone and main quality form the main sound
      - Modiao and coda quality form the coda sound
  - **单质干音**
    - Composed of a ganyin tone and a single quality final
    - The single quality final is represented by the nucleus
    - The ganyin tone is divided into second tone, main tone, and coda tone
    - The final is divided into onset quality, main quality, and coda quality (anterior, middle, and posterior parts of the final)
      - Onset tone and onset quality form the onset sound
      - Main tone and main quality form the main sound
      - Modiao and coda quality form the coda sound

**End**

- End of the yinyuan analysis

## Further Directions

**Detailed Explanation of Yinyuan Analysis**:
In the yinyuan analysis model, each syllable is analyzed into a yinyuan sequence.
In this model, the syllable is first split into jiediao (tonal layer) and jiezhi (qualitative layer). The tonal layer is further divided into shoudiao (initial tone) and gandiao (rime tone), while the qualitative layer is split into shengmu (onset quality) and yunmu (rime quality). These components are then recombined into huyin (onset+second tone), zhuyin (rime core+rime core tone), and moyin (rime tail+rime tail tone), which finally merge into yunyin (rime complex) to complete the syllable.

In this analysis, a syllable consists of a shouyin and a ganyin. The shouyin is the segment at the beginning of the syllable, composed of a shoudiao and a shouzhi. The shoudiao is the tonal segment connected to the shouzhi. The ganyin is the segment excluding the shouyin, composed of a ganyin tone and a final. The ganyin tone is the tonal segment connected to the final. Phonetic variables are divided into noise and musical sound. The shouyin is always represented by unpitched sound. The ganyin is always represented by sequences of pitched sound.

干音, according to the structure of the final, is divided into tri-quality ganyin, front long ganyin, back long ganyin, and single quality ganyin. Tri-quality ganyin is composed of a ganyin tone and a tri-quality final. Front long ganyin is composed of a ganyin tone and a front long final. Back long ganyin is composed of a ganyin tone and a back long final. Single quality ganyin is composed of a ganyin tone and a single quality final.

In tri-quality ganyin, the tri-quality final consists of a medial, nucleus, and coda. Correspondingly, the ganyin tone is divided into three segments: the segment connected to the medial, the segment connected to the nucleus, and the segment connected to the coda, abbreviated as second tone, main tone, and coda tone. Onset tone and medial form the onset sound. Main tone and nucleus form the main sound. Modiao and coda form the coda sound. The onset sound is simply the second yinyuan in the syllable. The main sound is the most important yinyuan in the syllable. The coda sound is the yinyuan at the end of the syllable.

In front long ganyin, the front long final consists of a nucleus and coda. Correspondingly, the ganyin tone is divided into two segments: the segment connected to the nucleus and the segment connected to the coda, abbreviated as medial tone and coda tone. Hudiao and nucleus form the medial sound. Modiao and coda form the coda sound. The medial sound is the segment between the shouyin and the coda sound. Since the medial tone corresponds to the second tone and main tone of the tri-quality ganyin, the medial tone is divided into second tone and main tone. Correspondingly, the medial sound is divided into onset sound and main sound.

In back long ganyin, the back long final consists of a medial and a nucleus. Correspondingly, the ganyin tone is divided into two segments: the segment connected to the medial and the segment connected to the nucleus, abbreviated as second tone and rhyme tone. Onset tone and medial form the onset sound. Rhyme tone and nucleus form the rhyme sound. The rhyme sound refers to the segment formed by the rhyme tone and the rhyme base or rhyme body. Since the rhyme tone corresponds to the main tone and coda tone of the tri-quality ganyin, the rhyme tone is divided into main tone and coda tone. Correspondingly, the rhyme sound is divided into main sound and coda sound.

In single quality ganyin, the single quality final is represented by the nucleus. Correspondingly, the ganyin tone is the segment connected to the final, which is the tone of the ganyin. Since the ganyin tone corresponds to the second tone, main tone, and coda tone of the tri-quality ganyin, the ganyin tone is divided into second tone, main tone, and coda tone. Correspondingly, the ganyin is divided into onset sound, main sound, and coda sound.

**Application Scenarios of Yinyuan Analysis**:
Specific applications of the yinyuan analysis in speech recognition and speech synthesis.

**History and Development of Yinyuan Analysis**:
The development history of the yinyuan analysis.

### Yinyuan Analysis Process

<div style="display: flex; justify-content: center;">

```mermaid
graph TD
   YinyuanAnalysisProcess[音元分析流程]

```

</div>

```mermaid
graph LR
      DecomposingSyllable[音节]
            DecomposingSyllable --> |析取|SyllabicTone[节调]
            DecomposingSyllable --> |析取|SyllabicQuality[节质]
                  SyllabicTone --> |分出|首调[首调]
                  SyllabicTone --> |分出|干调[干调]
                  SyllabicQuality --> |分出|声母[声母]
                  SyllabicQuality --> |分出|韵母[韵母]


      subgraph ShouyinComposition["首音构成"]
          首调 --> |构成|DecomposingShouyin[首音]
          声母 --> |构成|DecomposingShouyin[首音]
          end
      subgraph GanyinComposition["干音构成"]
          干调 --> |构成|DecomposingGanyin[干音]
          韵母 --> |构成|DecomposingGanyin[干音]
          end
      subgraph 首音和干音["首音和干音的类型"]
          subgraph ShouyinCategories["干音类型"]
              DecomposingShouyin --> |分类|XuShouyin[虚首音]
              DecomposingShouyin --> |分类|ShiShouyin[实首音]
          end
          subgraph GanyinCategories["干音类型"]
              DecomposingGanyin --> |分类|TriQualityGanyin[三质干音]
              DecomposingGanyin --> |分类|FrontLongGanyin[前长干音]
              DecomposingGanyin --> |分类|BackLongGanyin[后长干音]
              DecomposingGanyin --> |分类|SingleQualityGanyin[单质干音]
          end
      end
   subgraph 分析["首音和干音的解析"]
    subgraph 首音分析["首音解析"]
        XuShouyin --> |虚首音的音调从形式上被分析为默认值|零声母[实际上就是零声母]
        ShiShouyin --> |实首音的音调从形式上被分析为默认值|非零声母[实际就是非零声母]
      end

      subgraph DecomposingSingleQualityGanyin["单质干音解析"]

      SingleQualityGanyin --> |析取|SQGandiao[干调]
      SQGandiao --> |分出|SQHudiao[呼调]
      SQGandiao --> |分出|SQYundiao[韵调]
      SQYundiao --> |分出|SQZhudiao[主调]
      SQYundiao --> |分出|SQModiao[末调]

      SingleQualityGanyin --> |析取|SQGanzhi[单质韵母]
      SQGanzhi --> |分出|SQHuzhi[韵母前段]
      SQGanzhi --> |分出|SQYunzhi[韵质]
      SQYunzhi --> |分出|SQZhuzhi[韵母中段]
      SQYunzhi --> |分出|SQMozhi[韵母后段]

      end

      subgraph DecomposingBackLongGanyin["后长干音解析"]

      BackLongGanyin --> |析取|BLGandiao[干调]
      BLGandiao --> |分出|BLHudiao[呼调]
      BLGandiao --> |分出|BLYundiao[韵调]
      BLYundiao --> |分出|BLZhudiao[主调]
      BLYundiao --> |分出|Modiao[末调]

      BackLongGanyin --> |析取|BLGanzhi[后长韵母]
      BLGanzhi --> |分出|BLHuzhi[韵头]
      BLGanzhi --> |分出|BLYunzhi[韵腹]
      BLYunzhi --> |分出|BLZhuzhi[韵腹前段]
      BLYunzhi --> |分出|BLMozhi[韵腹后段]

      end

      subgraph DecomposingFrontLongGanyin["前长干音解析"]

      FrontLongGanyin --> |析取|FLGandiao[干调]
      FLGandiao --> |分出|FLJiandiao[间调]
      FLJiandiao --> |分出|FLHudiao[呼调]
      FLJiandiao --> |分出|FLZhudiao[主调]
      FLGandiao --> |分出|FLModiao[末调]

      FrontLongGanyin --> |析取|FLGanzhi[前长韵母]
      FLGanzhi --> |分出|FLJianzhi[韵腹]
      FLJianzhi --> |分出|FLHuzhi[韵腹前段]
      FLJianzhi --> |分出|FLZhuzhi[韵腹后段]
      FLGanzhi --> |分出|FLMozhi[韵尾]

      end

      subgraph DecomposingTriQualityGanyin["三质干音解析"]

      TriQualityGanyin --> |析取|TQGandiao[干调]
      TQGandiao --> |分出|TQHudiao[呼调]
      TQGandiao --> |分出|TQYundiao[韵调]
      TQYundiao --> |分出|TQZhudiao[主调]
      TQYundiao --> |分出|TQModiao[末调]

      TriQualityGanyin --> |析取|TQGanzhi[三质韵母]
      TQGanzhi --> |分出|TQHuzhi[韵头]
      TQGanzhi --> |分出|TQYunzhi[韵质]
      TQYunzhi --> |分出|TQZhuzhi[韵腹]
      TQYunzhi --> |分出|TQMozhi[韵尾]

      end
   end

   subgraph Yinyuan["音元分析"]
   零声母[实际上就是零声母] --> |分析|Zaoyin[噪音]
   非零声母[实际就是非零声母] --> |分析|Zaoyin[噪音]

   SQHudiao --> |构成|SQYueyin1[乐音]
   SQHuzhi --> |构成|SQYueyin1[乐音]
   SQZhudiao --> |构成|SQYueyin2[乐音]
   SQZhuzhi --> |构成|SQYueyin2[乐音]
   SQModiao --> |构成|SQYueyin3[乐音]
   SQMozhi --> |构成|SQYueyin3[乐音]

   BLHudiao --> |构成|BLYueyin1[乐音]
   BLHuzhi --> |构成|BLYueyin1[乐音]
   BLZhudiao --> |构成|BLYueyin2[乐音]
   BLZhuzhi --> |构成|BLYueyin2[乐音]
   Modiao --> |构成|BLYueyin3[乐音]
   BLMozhi --> |构成|BLYueyin3[乐音]

   FLHudiao --> |构成|FLYueyin1[乐音]
   FLHuzhi --> |构成|FLYueyin1[乐音]
   FLZhudiao --> |构成|FLYueyin2[乐音]
   FLZhuzhi --> |构成|FLYueyin2[乐音]
   FLModiao --> |构成|FLYueyin3[乐音]
   FLMozhi --> |构成|FLYueyin3[乐音]

   TQHudiao --> |构成|TQYueyin1[乐音]
   TQHuzhi --> |构成|TQYueyin1[乐音]
   TQZhudiao --> |构成|TQYueyin2[乐音]
   TQZhuzhi --> |构成|TQYueyin2[乐音]
   TQModiao --> |构成|TQYueyin3[乐音]
   TQMozhi --> |构成|TQYueyin3[乐音]
   end
   subgraph SyllableStructureModel["音元分析的音节层次结构模型"]
    subgraph 音元层["音元层"]
    Zaoyin --> |充当|音元层首音[首音]
    SQYueyin1 --> |充当|Huyin[呼音]
    SQYueyin2 --> |充当|Zhuyin[主音]
    SQYueyin3 --> |充当|Moyin[末音]

    BLYueyin1 --> |充当|Huyin[呼音]
    BLYueyin2 --> |充当|Zhuyin[主音]
    BLYueyin3 --> |充当|Moyin[末音]

    FLYueyin1 --> |充当|Huyin[呼音]
    FLYueyin2 --> |充当|Zhuyin[主音]
    FLYueyin3 --> |充当|Moyin[末音]

    TQYueyin1 --> |充当|Huyin[呼音]
    TQYueyin2 --> |充当|Zhuyin[主音]
    TQYueyin3 --> |充当|Moyin[末音]
    end

    subgraph 韵音层["韵音层"]
    音元层首音 --> |升级|YunyinLayerShouyin[首音]
    Huyin --> |升级|YunyinLayerHuyin[呼音]
    Zhuyin --> |构成|Yunyin[韵音]
    Moyin --> |构成|Yunyin[韵音]
    end
    subgraph 干音层["干音层"]
    YunyinLayerShouyin --> |升级|GanyinLayerShouyin[首音]
    YunyinLayerHuyin --> |构成|干音[干音]
    Yunyin --> |构成|干音[干音]
    end

    GanyinLayerShouyin[首音] --> |构成|音节[音节]
    干音 --> |构成|音节[音节]
   end
```

### Key Terminology

1. **音节(Mandarin Syllable)**
   - 音节 = **首音** + **干音**
   - 音节 = **节调** + **节质**
     - 节调 (Syllabic Tone or Tonal Layer)
     - 节质 (Syllabic Quality or Qualitative Layer)
     - 节调 = 首调 + 干调
       - 首调 = Tone of 首音
       - 干调 = Tone of 干音
     - 节质 = 声母 + 韵母
       - 声母 = Quality of 首音 = 声母
       - 韵母 = Quality of 干音 = 韵母

2. **首音**
   - 首音 = 首调 + Shouzhi
     - 首调 = Tonal Segment Connected to the 声母
     - Shouzhi = Quality of the 首音 = 声母 = 声母
3. **干音**
   - 干音 = 干调 + Ganzhi
     - 干调 = Tonal Segment Connected to the 韵母
     - Ganzhi = Quality of the 干音 = 韵母 = 韵母
4. **Categories of 干音**
   - 三质干音 = 干调 + 三质韵母
   - 前长干音 = 干调 + 前长韵母
   - 后长干音 = 干调 + 后长韵母
   - 单质干音 = 干调 + 单质韵母
5. **Yinyuan Composition**
   - Huyin = Hudiao + Huzhi
   - Zhuyin = Zhudiao + Zhuzhi
   - Moyin = Modiao + Mozhi
     - Hudiao = Tonal Segment Connected to the Huzhi
     - Zhudiao = Tonal Segment Connected to the Zhuzhi
     - Modiao = Tonal Segment Connected to the Mozhi
     - Jiandiao = Tonal Segment Connected to the Jianzhi
     - Yundiao = Tonal Segment Connected to the Yunzhi
     - Huzhi = Head of the 韵母 / Anterior part of the nucleus in front long final / Anterior part of single quality final
     - Zhuzhi = Nucleus of the tri-quality final / Posterior part of the nucleus in front long final / Anterior part of the nucleus in back long final / Middle part of single quality final
     - Mozhi = Tail of the 韵母 / Posterior part of the nucleus in back long final / Posterior part of single quality final
6. **音节 Structure**
   - 音节 = 首音 + Huyin + Zhuyin + Moyin
   - 音节 = 首音 + Huyin + Yunyin
   - 音节 = 首音 + 干音

   - 干音 = Huyin + Yunyin
   - Yunyin = Zhuyin + Moyin
   -
   - 音节 = 首音 + Jianyin + Moyin
   - Jianyin = Huyin + Zhuyin

# Yinyuan Analysis Process

## Description of the Yinyuan Analysis Process

**Start**

- Begin the yinyuan (phonetic variable) analysis

**Syllable Analysis**

- Each Syllable (syllable) is analyzed into a yinyuan sequence

**首音 and SubsequentSound**

- A syllable consists of a initial sound and a subsequent sound (final with tone  or divisional rhyme)
  - **首音**
    - Composed of a shoudiao and a shouzhi
      - The shoudiao is the tonal segment connected to the shouzhi
      - The initial sound is represented by unpitched sound
  - **SubsequentSound**
    - Composed of a subsequent sound tone and a final
      - The subsequent sound tone is the tonal segment connected to the final
      - The subsequent sound is represented by sequences of pitched sound
  - **Yinyuan**
    - The yinyuan is the set of unpitched and pitched sounds that make up all syllables

**SubsequentSound Classification**

- SubsequentSound is divided into four types:
  - **三质干音**
    - Composed of a subsequent sound tone and a tri-quality final
      - The tri-quality final consists of a medial, nucleus, and coda
      - The subsequent sound tone is divided into second tone, main tone, and coda tone
      - Onset tone and medial form the onset sound
      - Main tone and nucleus form the main sound
      - LastPitch and coda form the coda sound
  - **前长干音**
    - Composed of a subsequent sound tone and a front long final
    - The front long final consists of a nucleus and coda
    - The subsequent sound tone is divided into medial tone and coda tone
      - SecondPitch and nucleus form the medial sound
      - SecondPitch is further divided into second tone and main tone
      - The nucleus is divided into onset quality and main quality (anterior and posterior parts of the nucleus)
      - Onset tone and onset quality form the onset sound
      - Main tone and main quality form the main sound
      - LastPitch and coda form the coda sound
  - **后长干音**
    - Composed of a subsequent sound tone and a back long final
    - The back long final consists of a medial and a nucleus
    - The subsequent sound tone is divided into second tone and rhyme tone
      - Onset tone and medial form the onset sound
      - Rhyme tone and nucleus form the rhyme sound
      - Rhyme tone is further divided into main tone and coda tone
      - The nucleus is divided into main quality and coda quality (anterior and posterior parts of the nucleus)
      - Main tone and main quality form the main sound
      - LastPitch and coda quality form the coda sound
  - **单质干音**
    - Composed of a subsequent sound tone and a single quality final
    - The single quality final is represented by the nucleus
    - The subsequent sound tone is divided into second tone, main tone, and coda tone
    - The final is divided into onset quality, main quality, and coda quality (anterior, middle, and posterior parts of the final)
      - Onset tone and onset quality form the onset sound
      - Main tone and main quality form the main sound
      - LastPitch and coda quality form the coda sound

**End**

- End of the yinyuan analysis

## Further Directions

**Detailed Explanation of Yinyuan Analysis**:
In the yinyuan analysis model, each syllable is analyzed into a yinyuan sequence.
In this model, the syllable is first split into jiediao (tonal layer) and jiezhi (qualitative layer). The tonal layer is further divided into shoudiao (initial tone) and subsequent Tone segment, while the qualitative layer is split into shengmu (onset quality) and yunmu (rime quality). These components are then recombined into huyin (onset+second tone), zhuyin (rime core+rime core tone), and moyin (rime tail+rime tail tone), which finally merge into yunyin (rime complex) to complete the syllable.

In this analysis, a syllable consists of a initial sound and a subsequent sound. The initial sound is the segment at the beginning of the syllable, composed of a shoudiao and a shouzhi. The shoudiao is the tonal segment connected to the shouzhi. The subsequent sound is the segment excluding the initial sound, composed of a subsequent sound tone and a final. The subsequent sound tone is the tonal segment connected to the final. Phonetic variables are divided into noise and musical sound. The initial sound is always represented by unpitched sound. The subsequent sound is always represented by sequences of pitched sound.

SubsequentSound, according to the structure of the final, is divided into tri-quality subsequent sound, front long subsequent sound, back long subsequent sound, and single quality subsequent sound. Tri-quality subsequent sound is composed of a subsequent sound tone and a tri-quality final. Front long subsequent sound is composed of a subsequent sound tone and a front long final. Back long subsequent sound is composed of a subsequent sound tone and a back long final. Single quality subsequent sound is composed of a subsequent sound tone and a single quality final.

In tri-quality subsequent sound, the tri-quality final consists of a medial, nucleus, and coda. Correspondingly, the subsequent sound tone is divided into three segments: the segment connected to the medial, the segment connected to the nucleus, and the segment connected to the coda, abbreviated as second tone, main tone, and coda tone. Onset tone and medial form the onset sound. Main tone and nucleus form the main sound. LastPitch and coda form the coda sound. The onset sound is simply the second yinyuan in the syllable. The main sound is the most important yinyuan in the syllable. The coda sound is the yinyuan at the end of the syllable.

In front long subsequent sound, the front long final consists of a nucleus and coda. Correspondingly, the subsequent sound tone is divided into two segments: the segment connected to the nucleus and the segment connected to the coda, abbreviated as medial tone and coda tone. SecondPitch and nucleus form the medial sound. LastPitch and coda form the coda sound. The medial sound is the segment between the initial sound and the coda sound. Since the medial tone corresponds to the second tone and main tone of the tri-quality subsequent sound, the medial tone is divided into second tone and main tone. Correspondingly, the medial sound is divided into onset sound and main sound.

In back long subsequent sound, the back long final consists of a medial and a nucleus. Correspondingly, the subsequent sound tone is divided into two segments: the segment connected to the medial and the segment connected to the nucleus, abbreviated as second tone and rhyme tone. Onset tone and medial form the onset sound. Rhyme tone and nucleus form the rhyme sound. The rhyme sound refers to the segment formed by the rhyme tone and the rhyme base or rhyme body. Since the rhyme tone corresponds to the main tone and coda tone of the tri-quality subsequent sound, the rhyme tone is divided into main tone and coda tone. Correspondingly, the rhyme sound is divided into main sound and coda sound.

In single quality subsequent sound, the single quality final is represented by the nucleus. Correspondingly, the subsequent sound tone is the segment connected to the final, which is the tone of the subsequent sound. Since the subsequent sound tone corresponds to the second tone, main tone, and coda tone of the tri-quality subsequent sound, the subsequent sound tone is divided into second tone, main tone, and coda tone. Correspondingly, the subsequent sound is divided into onset sound, main sound, and coda sound.

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
  subgraph InputSyllable["输入音节"]
      DecomposingSyllable[音节]
  end
  subgraph ExtractTonalQuality["质调二分"]
      DecomposingSyllable --> |析取|SyllabicTone[节调]
      DecomposingSyllable --> |析取|SyllabicQuality[节质]
  end
  subgraph QualitativeLayer["质调分段"]
      subgraph ToneDichotomy["节调二分"]
        SyllabicTone --> |切分|InitialTonalSegment[首调]
        SyllabicTone --> |切分|SubsequentTonalSegment[干调]
      end
      subgraph QualityDichotomy["节质二分"]
        SyllabicQuality --> |切分|InitialConsonant[声母]
        SyllabicQuality --> |切分|Final[韵母]
      end
  end
  subgraph HeadBody["首干二分"]
      subgraph SyllableInitialSound["音节首音"]
        InitialTonalSegment --> |构成|DecomposingInitialSound[首音]
        InitialConsonant --> |构成|DecomposingInitialSound[首音]
      end
      subgraph SyllableSubsequentSound["音节干音"]
        SubsequentTonalSegment --> |构成|DecomposingSubsequentSound[干音]
        Final --> |构成|DecomposingSubsequentSound[干音]
      end
  end
  subgraph InitialAndSubsequentSoundCategories["首音和干音的分类"]
      subgraph InitialSoundCategories["首音类型"]
        DecomposingInitialSound --> |分类|InsubstantialInitialSound[虚首音]
        DecomposingInitialSound --> |分类|SubstantialInitialSound[实首音]
      end
      subgraph SubsequentSoundCategories["干音类型"]
        DecomposingSubsequentSound --> |分类|TriQualitySubsequentSound[三质干音]
        DecomposingSubsequentSound --> |分类|FrontLongSubsequentSound[前长干音]
        DecomposingSubsequentSound --> |分类|BackLongSubsequentSound[后长干音]
        DecomposingSubsequentSound --> |分类|SingleQualitySubsequentSound[单质干音]
      end
    end
   subgraph InitialAndSubsequentSoundDecompose["首音和干音的分析"]
    subgraph InitialSoundAnalysis["虚实首音分析"]
        InsubstantialInitialSound --> |析取|InsubstantialInitialSoundTone[首调] --> |分析--非稳定的规律性的音调且非区别性特征|InitialSoundTone[首调]
        InsubstantialInitialSound --> |析取|InsubstantialInitialSoundQuality[零声母] --> |分析并更名--除阻辅音的音质且非区别性特征|InitialSoundQuality[首质]

        SubstantialInitialSound --> |析取|SubstantialInitialSoundTone[首调] --> |分析--非稳定的规律性的音调且非区别性特征|InitialSoundTone[首调]
        SubstantialInitialSound --> |析取|SubstantialInitialSoundQuality[非零声母] --> |分析并更名--除阻辅音的音质且是区别性特征|InitialSoundQuality[首质]
      end

      subgraph DecomposingSingleQualitySubsequentSound["单质干音分析"]

      SingleQualitySubsequentSound --> |析取|SQTone[干调]
      SQTone --> |切分|SQSecondPitch[呼调]
      SQTone --> |切分|SQRimeTone[韵调]
      SQPitch --> |切分|SQMainPitch[主调]
      SQRimeTone --> |切分|SQLastPitch[末调]

      SingleQualitySubsequentSound --> |析取|SQFinal[单质韵母]
      SQFinal --> |切分|SQFinalAnteriorSegment[韵母前段]
      SQFinal --> |切分|SQRimeQuality[韵质]
      SQRimeQuality --> |切分|SQFinalMiddleSegment[韵母中段]
      SQRimeQuality --> |切分|SQFinalPosteriorSegment[韵母后段]

      end

      subgraph DecomposingBackLongSubsequentSound["后长干音分析"]

      BackLongSubsequentSound --> |析取|BLTone[干调]
      BLTone --> |切分|BLSecondPitch[呼调]
      BLTone --> |切分|BLRimeTone[韵调]
      BLRimeTone --> |切分|BLMainPitch[主调]
      BLRimeTone --> |切分|LastPitch[末调]

      BackLongSubsequentSound --> |析取|BLFinal[后长韵母]
      BLFinal --> |切分|BLFinalHead[韵头]
      BLFinal --> |切分|BLRimeQuality[韵腹]
      BLRimeQuality --> |切分|BLFinalNucleusAnteriorSegment[韵腹前段]
      BLRimeQuality --> |切分|BLFinalNucleusPosteriorSegment[韵腹后段]

      end

      subgraph DecomposingFrontLongSubsequentSound["前长干音分析"]

      FrontLongSubsequentSound --> |析取|FLTone[干调]
      FLTone --> |切分|FLIntermediateTonalSegment[间调]
      FLIntermediateTonalSegment --> |切分|FLSecondPitch[呼调]
      FLIntermediateTonalSegment --> |切分|FLMainPitch[主调]
      FLTone --> |切分|FLLastPitch[末调]

      FrontLongSubsequentSound --> |析取|FLFinal[前长韵母]
      FLFinal --> |切分|FLIntermediateQuality[韵腹]
      FLIntermediateQuality --> |切分|FLFinalNucleusAnteriorSegment[韵腹前段]
      FLIntermediateQuality --> |切分|FLFinalNucleusPosteriorSegment[韵腹后段]
      FLFinal --> |切分|FLFinalRail[韵尾]

      end

      subgraph DecomposingTriQualitySubsequentSound["三质干音分析"]

      TriQualitySubsequentSound --> |析取|TQTone[干调]
      TQTone --> |切分|TQSecondPitch[呼调]
      TQTone --> |切分|TQRimeTone[韵调]
      TQRimeTone --> |切分|TQMainPitch[主调]
      TQRimeTone --> |切分|TQLastPitch[末调]

      TriQualitySubsequentSound --> |析取|TQFinal[三质韵母]
      TQFinal --> |切分|TQFinalHead[韵头]
      TQFinal --> |切分|TQRimeQuality[韵质]
      TQRimeQuality --> |切分|TQFinalMain[韵腹]
      TQRimeQuality --> |切分|TQFinalTail[韵尾]

      end
   end

   subgraph Yinyuan["音元分类"]
    subgraph YinyuanAnalysis["噪音分析"]
      InitialSoundTone --> |构成|UnpitchedSound[噪音]
      InitialSoundQuality --> |构成|UnpitchedSound[噪音]
    end
    subgraph YinyuanDecomposition["乐音分析"]
      SQSecondPitch --> |构成|SQPitchedSound1[乐音]
      SQFinalAnteriorSegment --> |构成|SQPitchedSound1[乐音]
      SQMainPitch --> |构成|SQPitchedSound2[乐音]
      SQFinalMiddleSegment --> |构成|SQPitchedSound2[乐音]
      SQLastPitch --> |构成|SQPitchedSound3[乐音]
      SQFinalPosteriorSegment --> |构成|SQPitchedSound3[乐音]

      BLSecondPitch --> |构成|BLPitchedSound1[乐音]
      BLFinalHead --> |构成|BLPitchedSound1[乐音]
      BLMainPitch --> |构成|BLPitchedSound2[乐音]
      BLFinalNucleusAnteriorSegment --> |构成|BLPitchedSound2[乐音]
      LastPitch --> |构成|BLPitchedSound3[乐音]
      BLFinalNucleusPosteriorSegment --> |构成|BLPitchedSound3[乐音]

      FLSecondPitch --> |构成|FLPitchedSound1[乐音]
      FLFinalNucleusAnteriorSegment --> |构成|FLPitchedSound1[乐音]
      FLMainPitch --> |构成|FLPitchedSound2[乐音]
      FLFinalNucleusPosteriorSegment --> |构成|FLPitchedSound2[乐音]
      FLLastPitch --> |构成|FLPitchedSound3[乐音]
      FLFinalRail --> |构成|FLPitchedSound3[乐音]

      TQSecondPitch --> |构成|TQPitchedSound1[乐音]
      TQFinalHead --> |构成|TQPitchedSound1[乐音]
      TQMainPitch --> |构成|TQPitchedSound2[乐音]
      TQFinalMain --> |构成|TQPitchedSound2[乐音]
      TQLastPitch --> |构成|TQPitchedSound3[乐音]
      TQFinalTail --> |构成|TQPitchedSound3[乐音]
    end

   end
   subgraph SyllableStructureModel["音元分析的音节层次结构模型"]
    subgraph ThirdLayer["音元层"]
    UnpitchedSound --> |充当|ThirdLayerInitial[首音]
    SQPitchedSound1 --> |充当|Huyin[呼音]
    SQPitchedSound2 --> |充当|Zhuyin[主音]
    SQPitchedSound3 --> |充当|Moyin[末音]

    BLPitchedSound1 --> |充当|Huyin[呼音]
    BLPitchedSound2 --> |充当|Zhuyin[主音]
    BLPitchedSound3 --> |充当|Moyin[末音]

    FLPitchedSound1 --> |充当|Huyin[呼音]
    FLPitchedSound2 --> |充当|Zhuyin[主音]
    FLPitchedSound3 --> |充当|Moyin[末音]

    TQPitchedSound1 --> |充当|Huyin[呼音]
    TQPitchedSound2 --> |充当|Zhuyin[主音]
    TQPitchedSound3 --> |充当|Moyin[末音]
    end

    subgraph SecondLayer["韵音层"]
      ThirdLayerInitial --> |升级|SecondLayerInitial[首音]
      Huyin --> |升级|SecondLayerHuyin[呼音]
      Zhuyin --> |构成|Yunyin[韵音]
      Moyin --> |构成|Yunyin[韵音]
    end
    subgraph FirstLayer["干音层"]
      SecondLayerInitial --> |升级|InitialSound[首音]
      SecondLayerHuyin --> |构成|SubsequentSound[干音]
      Yunyin --> |构成|SubsequentSound[干音]
    end
    subgraph SyllableLayer["音元序列"]
      InitialSound --> |构成|Syllable[音节]
      SubsequentSound --> |构成|Syllable[音节]
    end
   end
```

### Key Terminology

1. **Syllable(Mandarin Syllable)**
   - Syllable = **首音** + **SubsequentSound**
   - Syllable = **节调** + **节质**
     - 节调 (Syllabic Tone or Tonal Layer)
     - 节质 (Syllabic Quality or Qualitative Layer)
     - 节调 = 首调 + 干调
       - 首调 = Tone of 首音
       - 干调 = Tone of SubsequentSound
     - 节质 = 声母 + 韵母
       - 声母 = Quality of 首音 = 声母
       - 韵母 = Quality of SubsequentSound = 韵母

2. **首音**
   - 首音 = 首调 + Shouzhi
     - 首调 = Tonal Segment Connected to the 声母
     - Shouzhi = Quality of the 首音 = 声母 = 声母
3. **SubsequentSound**
   - SubsequentSound = 干调 + Final
     - 干调 = Tonal Segment Connected to the 韵母
     - Final = Quality of the SubsequentSound = 韵母 = 韵母
4. **Categories of SubsequentSound**
   - 三质干音 = 干调 + 三质韵母
   - 前长干音 = 干调 + 前长韵母
   - 后长干音 = 干调 + 后长韵母
   - 单质干音 = 干调 + 单质韵母
5. **Yinyuan Composition**
   - Huyin = SecondPitch + SecondQualitySegment
   - Zhuyin = MainPitch + Zhuzhi
   - Moyin = LastPitch + Mozhi
     - SecondPitch = Tonal Segment Connected to the SecondQualitySegment
     - MainPitch = Tonal Segment Connected to the Zhuzhi
     - LastPitch = Tonal Segment Connected to the Mozhi
     - Jiandiao = Tonal Segment Connected to the Jianzhi
     - RimeTone = Tonal Segment Connected to the RimeQuality
     - SecondQualitySegment = Head of the 韵母 / Anterior part of the nucleus in front long final / Anterior part of single quality final
     - Zhuzhi = Nucleus of the tri-quality final / Posterior part of the nucleus in front long final / Anterior part of the nucleus in back long final / Middle part of single quality final
     - Mozhi = Tail of the 韵母 / Posterior part of the nucleus in back long final / Posterior part of single quality final
6. **Syllable Structure**
   - Syllable = 首音 + Huyin + Zhuyin + Moyin
   - Syllable = 首音 + Huyin + Yunyin
   - Syllable = 首音 + SubsequentSound

   - SubsequentSound = Huyin + Yunyin
   - Yunyin = Zhuyin + Moyin
   -
   - Syllable = 首音 + Jianyin + Moyin
   - Jianyin = Huyin + Zhuyin

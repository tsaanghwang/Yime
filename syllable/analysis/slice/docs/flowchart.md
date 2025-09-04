```mermaid
graph TD
  %% 输入层
  subgraph Input["输入"]
    DecomposingSyllable[音节]
  end

%% 提取音调和音质
  subgraph ExtractQualityTone["提取音节的音调和音质"]
    subgraph ToneOfSyllable["音节的音调"]
      DecomposingSyllable --> |提取| SyllabicTone[节调]
    end
    subgraph QualityOfSyllable["音节的音质"]
      DecomposingSyllable --> |提取| SyllabicQuality[节质]
    end
  end

  %% 切分首音和干音
  subgraph SyllableDichotomy["切分首音和干音"]
    subgraph QualitativeLayer["节调和节质的二分"]
      subgraph ToneDichotomy["切分与声母和韵母联结的调段"]
        SyllabicTone --> |切分| InitialTonalSegment[首调]
        SyllabicTone --> |切分| SubsequentTonalSegment[干调]
      end
      subgraph QualityDichotomy["节质的声母和韵母"]
        SyllabicQuality --> |切分| InitialConsonant[声母]
        SyllabicQuality --> |切分| Final[韵母]
      end
    end

    %% 构成首音和干音
    InitialTonalSegment --> |构成| DecomposingInitialSound[首音]
    InitialConsonant --> |构成| DecomposingInitialSound
    SubsequentTonalSegment --> |构成| DecomposingSubsequentSound[干音]
    Final --> |构成| DecomposingSubsequentSound
  end

  %% 首音和干音分类
  subgraph InitialAndSubsequentSoundCategories["首音和干音的分类"]
    DecomposingInitialSound --> |分类| IsNotZeroInitial{声母类型}
    IsNotZeroInitial --> |是零声母| InsubstantialInitialSound[虚首音]
    IsNotZeroInitial --> |非零声母| SubstantialInitialSound[实首音]

    DecomposingSubsequentSound --> |分类| ChoiceFinalCategories{韵母类型}
    ChoiceFinalCategories --> |三质韵母| TriQualitySubsequentSound[三质干音]
    ChoiceFinalCategories --> |前长韵母| FrontLongSubsequentSound[前长干音]
    ChoiceFinalCategories --> |后长韵母| BackLongSubsequentSound[后长干音]
    ChoiceFinalCategories --> |单质韵母| SingleQualitySubsequentSound[单质干音]
  end



## 音元分析法的流程

音元分析法是把音节分析成音元序列的方法

在音元分析法中，音节由首音和干音构成。首音是音节开头的音段，由首调与声母构成。首调是与声母联结的调段。干音是除首音外的音段，由干调与韵母构成。干调是与韵母联结的调段。音元分成噪音和乐音两类。首音都由噪音充当。干音都由乐音构成

干音分成三质干音/前长干音/后长干音和单质干音四类。三质干音由干调与三质韵母构成。前长干音由干调与前长韵母构成。后长干音干调与后长韵母构成。单质干音由干调与单质韵母构成

在三质干音中，三质韵母由韵头/韵腹和韵尾构成。相对应地，干调分成与韵头联结的调段/与调腹联结的调段和与调尾联结的调段三段，依序称为二调/主调和末调。二调与韵头构成二音。主调与韵腹构成主音。末调与韵尾构成末音。二音意指构成音节的第二个音元。主音意指构成音节的最主要音元。末音意指构成音节的末尾的音元

在前长干音中，前长韵母由韵腹和韵尾构成。相对应地，干调分成与韵腹联结的调段和与韵尾联结的调段两段，依序称为间调和末调。间调与韵腹构成间音。末调与韵尾构成末音。间音意指间居在首音和末音间的音段。由于间调与三质干音的由二调和主调构成的间调对应相同，所以间调分成二调和主调两段。相对应地，间音分成二音和主音两段

在后长干音中，后长韵母由韵头和韵腹构成。相对应地，干调分成与韵头联结的调段和与韵腹联结的调段两段，依序称为二调和韵调。二调与韵头构成二音。韵调与韵腹构成韵音。韵音指韵调与韵基或韵身构成的音段。由于韵调与三质干音的由主调和末调构成的韵调对应相同，所以韵调分成主调和末调两段。相对应地，韵音分成主音和末音两段

在单质干音中，单质韵母由韵腹充当。相对应地，干调就是与韵母联结的调段，就是干音的音调。由于干调与三质干音的由二调/主调和末调构成的干调对应相同，所以干调分成二调/主调和末调三段。相对应地，干音分成二音/主音和末音三段

音元分析法的流程图如下

## 音元分析法流程图描述

**开始**

- 音元分析法开始

**音节分析**

- 音节被分析成音元序列

**首音与干音**

- 音节由首音和干音构成
  - **首音**
    - 由首调与声母构成
    - 首调是与声母联结的调段
    - 首音由噪音充当
    - **干音**
      - 由干调与韵母构成
        - 干调是与韵母联结的调段
        - 干音由乐音构成

**干音分类**

- 干音分成四类:
  - **三质干音**
    - 由干调与三质韵母构成
      - 三质韵母由韵头/韵腹和韵尾构成
      - 干调分成二调/主调和末调
        - 二调与韵头构成二音
        - 主调与韵腹构成主音
        - 末调与韵尾构成末音
    - **前长干音**
      - 由干调与前长韵母构成
      - 前长韵母由韵腹和韵尾构成
      - 干调分成间调和末调
        - 间调与韵腹构成间音
        - 末调与韵尾构成末音
    - **后长干音**
      - 由干调与后长韵母构成
      - 后长韵母由韵头和韵腹构成
      - 干调分成二调和韵调
        - 二调与韵头构成二音
        - 韵调与韵腹构成韵音
    - **单质干音**
      - 由干调与单质韵母构成
      - 单质韵母由韵腹充当
      - 干调分成二调/主调和末调
        - 二调/主调和末调分别构成二音/主音和末音

**结束**

- 音元分析法结束

## 延伸方向

**音元分类的详细解释**：您可以进一步了解噪音和乐音的具体分类标准。

**音元分析法的应用场景**：了解音元分析法在语音识别和语音合成中的具体应用。

**音元分析法的历史与发展**：探索音元分析法的起源及其在语言学中的发展历程。

Based on the description of **Sound Element Analysis (音元分析法)**, here's the English terminology flowchart structure:

### Sound Element Analysis Flowchart

```mermaid
flowchart TD
   A[Syllable] --> B[Initial Sound]
   A --> C[Core Sound]

   subgraph Initial_Sound["Initial Sound Details"]
   B --> B1[Initial Tone + Initial Consonant]
   B1 --> B2[Noise]
   end
   
   C --> D[Tri-Element Core Sound]
   C --> E[Front-Weighted Core Sound]
   C --> F[Back-Weighted Core Sound]
   C --> G[Single-Element Core Sound]

   subgraph Tri_Element["Tri-Element Core Sound Details"]
   D --> D1[Core Tone Division: Secondary Tone + Primary Tone + Final Tone]
   D1 --> D11[Secondary Sound: Secondary Tone + Head Vowel]
   D1 --> D12[Primary Sound: Primary Tone + Main Vowel]
   D1 --> D13[Final Sound: Final Tone + Tail Vowel]
   end

   subgraph Front_Weighted["Front-Weighted Core Sound Details"]
   E --> E1[Core Tone Division: Medial Tone + Final Tone]
   E1 --> E11[Medial Tone Division: Secondary Tone + Primary Tone]
   E11 --> E111[Secondary Sound]
   E11 --> E112[Primary Sound]
   E1 --> E12[Final Sound]
   end

   subgraph Back_Weighted["Back-Weighted Core Sound Details"]
   F --> F1[Core Tone Division: Secondary Tone + Rhyme Tone]
   F1 --> F11[Secondary Sound]
   F1 --> F12[Rhyme Tone Division: Primary Tone + Final Tone]
   F12 --> F121[Primary Sound]
   F12 --> F122[Final Sound]
   end

   subgraph Single_Element["Single-Element Core Sound Details"]
   G --> G1[Core Tone Division: Secondary Tone + Primary Tone + Final Tone]
   G1 --> G11[Secondary Sound]
   G1 --> G12[Primary Sound]
   G1 --> G13[Final Sound]
   end
   ```

### Key Terminology

1. **音元 (Sound Element)**
   - Syllable → **Initial Sound** + **Core Sound**
2. **首音 (Initial Sound)**
   - 首调 (Initial Tone) + 声母 (Initial Consonant)
3. **干音 (Core Sound)**
   - 干调 (Core Tone) + 韵母 (Final)
4. **四类干音 (Core Sound Types)**
   - 三质干音 (Tri-Element Core Sound)
   - 前长干音 (Front-Weighted Core Sound)
   - 后长干音 (Back-Weighted Core Sound)
   - 单质干音 (Single-Element Core Sound)
5. **调段分级 (Tone Segmentation)**
   - 二调 (Secondary Tone)
   - 主调 (Primary Tone)
   - 末调 (Final Tone)
   - 间调 (Medial Tone)
   - 韵调 (Rhyme Tone)
6. **音元组成 (Sound Element Formation)**
   - 二音 (Secondary Sound)
   - 主音 (Primary Sound)
   - 末音 (Final Sound)

This flowchart maintains the structural logic while using standardized linguistic terminology. The color-free format works universally for documentation. If you need a visual diagram file (PNG/SVG) or detailed term definitions, I can generate them separately.

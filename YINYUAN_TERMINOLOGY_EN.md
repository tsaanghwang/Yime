# Terminology of the Yinyuan System

## Abstract

The Yinyuan system is best understood as a general analytic framework in which speech is segmented by the contrastive properties that matter in a given language. In this system, a `pianyin` is a temporally cut speech-sound slice, and a `yinyuan` is an abstract unit occupying a temporal slot and instantiated by a class of such slices. In the Modern Standard Chinese case, pitch and quality are the principal contrastive properties, but that Chinese-specific profile should not be mistaken for the theory-wide definition.

## Scope

This document defines several key terms used in the Yinyuan system, together with their intended English renderings and their relation to more familiar concepts in phonetics and phonology.

The goal is not to force the Yinyuan system into the exact terminology of traditional phonemics or traditional phonetics. Instead, this document clarifies:

1. which existing English words can be reused,
2. which terms require a system-specific definition, and
3. how these terms differ from phoneme-, phone-, segment-, or tone-tier-based analyses.

## Central Claim

The Yinyuan system is not merely a special tool for tonal languages. More fundamentally, it is a general framework that allows speech to be segmented by whatever speech properties are contrastive in a given language.

This means that:

1. speech need not be segmented by quality alone,
2. pitch, intensity, duration, and similar properties need not be treated in advance as merely accessory to the whole syllable, and
3. different languages may instantiate different special cases within the same framework.

In the Modern Standard Chinese case, the framework differs sharply from the traditional phonemic system because speech is segmented jointly by pitch and quality. Formally, even consonantal noise is included in the same system, except that its pitch value is taken to be zero or null.

Accordingly, the basic units of the Yinyuan system cannot simply be identified with the traditional phoneme, phone, or segment.

## Terminology at a Glance

| Chinese term | Recommended English | Short definition |
| --- | --- | --- |
| 时段 | `temporal slot` | A temporally extended position or span in the speech stream that can be occupied by a speech unit. |
| 片音 | `phonic slice` | A speech-sound slice cut in the temporal dimension; not simply a traditional phone or segment. |
| 音元 | `yinyuan` | An abstract unit occupying a temporal slot and defined by the contrastive speech properties relevant in a given language. |

## Citation-Ready Definitions

These short definitions are intended for reuse in papers, summaries, or externally facing explanations.

- `Pianyin`: A `pianyin` is a phonic slice, namely a speech-sound slice cut in the temporal dimension. It may be smaller than a traditional segment, though in some cases it may coincide with one.
- `Yinyuan`: A `yinyuan` is an abstract unit occupying a temporal slot in the speech stream and defined by the contrastive speech properties relevant in a given language. It is not mapped to any single phonic slice, but is instantiated by a class of phonic slices.

## Glossary

### 1. Temporal Slot

- Chinese term: 时段
- Recommended English: temporal slot

Here, slot does not mean a purely abstract placeholder. It refers to a temporally extended position or span in the speech stream that can be occupied by a speech unit.

When brevity is needed and the context is clear, slot may be used by itself. In formal definition, however, temporal slot is preferred.

### 2. Pianyin

- Chinese term: 片音
- Recommended English: phonic slice

Pianyin should not be equated with the traditional phone, nor is phonetic segment an adequate translation.

The reason is that a pianyin is defined in the temporal dimension:

1. it is a slice cut out of the speech stream,
2. it may be smaller than a traditional segment, for example when a relatively long vowel or nasal is split into two or three temporally distinct portions, and
3. in some cases it may coincide with a traditional segment, for example certain onset consonants.

For that reason, phonic slice is preferred over phonetic segment.

### 3. Yinyuan

- Chinese term: 音元
- Recommended English: yinyuan

Yinyuan is an abstract unit in the Yinyuan system. Its definition contains three essential components:

1. it occupies a temporal slot,
2. it is defined by the contrastive speech properties relevant in the language under analysis, and
3. it is not mapped to a single pianyin, but instantiated by a class of pianyin.

For that reason, yinyuan should not simply be rendered as:

- phoneme,
- segment, or
- slot-based phonological unit.

The first two terms would collapse it back into the traditional phonemic or segmental framework. The third term preserves the temporal-slot aspect, but omits the crucial fact that segmentation is determined by the language's own contrastive properties.

For the present stage of the theory, the safest practice is to use `yinyuan` itself as the primary English label and then add an explanatory gloss when needed.

In discussions specifically limited to Modern Standard Chinese, `pitch-quality slot unit` may still be used as a working gloss. Even there, however, it should be understood as a Chinese-case description rather than as the global definition of the theory.

### 4. Relation Between Pianyin and Yinyuan

The relation between pianyin and yinyuan is not one of one-to-one correspondence.

It is closer to the relation between:

- phone and phoneme,
- instance and abstract class, or
- runtime value and variable in programming.

More precisely:

1. a pianyin is a concrete slice of speech cut out from the speech stream,
2. a yinyuan is an abstract unit obtained by grouping such slices according to the contrastive criteria relevant in the language under analysis, and
3. a single yinyuan may be instantiated by a set or class of pianyin rather than by one single pianyin.

Therefore it is inaccurate to say that a yinyuan corresponds to a phonic slice. It is more accurate to say that:

- a yinyuan is instantiated by a class of phonic slices, and
- a pianyin is a concrete realization value of a yinyuan.

## Extended Definition Notes

The concise definitions above are the recommended forms for citation. The present section keeps the surrounding explanatory context.

### Yinyuan

> A yinyuan is an abstract unit occupying a temporal slot in the speech stream and defined by the contrastive speech properties relevant in a given language. It is not mapped to any single phonic slice, but is instantiated by a class of phonic slices.

### Pianyin

> A pianyin is a phonic slice, namely a speech-sound slice cut in the temporal dimension. It may be smaller than a traditional segment, though in some cases it may coincide with one.

## From the General Framework to Language-Specific Cases

In a broader theoretical sense, the Yinyuan framework allows phonic slices to be segmented and yinyuan to be determined by multiple contrastive speech properties. In its widest formulation, these properties may include:

1. pitch,
2. intensity,
3. quality, and
4. duration.

Different languages, however, do not use the same set of properties to distinguish meaning. The yinyuan system of a given language may therefore be understood as a language-specific realization of a more general framework.

### A language that distinguishes meaning only by quality

If a language distinguishes meaning only by quality, while pitch, intensity, and duration remain non-distinctive, then its yinyuan system effectively reduces to a phonemic system.

In such a case:

1. yinyuan may still be retained as a theoretical term,
2. but the actual analysis does not differ substantially from traditional phonemic analysis.

A simple hypothetical example would be a language in which contrasts such as `pa`, `ba`, `ta`, and `da` are meaningful, while pitch, intensity, and duration are always predictable defaults and never distinguish morphemic meaning. Under such conditions, the yinyuan system is equivalent to the phonemic system.

English may be treated as an approximate example of this type if one abstracts away from certain complications involving stress, duration, and intonation.

### A language that distinguishes meaning by all four properties

If a language distinguishes meaning simultaneously by pitch, intensity, quality, and duration, then its yinyuan system would represent a fully developed all-feature yinyuan system.

In such a language:

1. none of the four properties would be merely default or accessory,
2. and all four could serve as distinctive criteria in segmenting phonic slices and determining yinyuan.

A hypothetical example would be a language in which `a`, high-pitched `á`, intensified `a`, and long `aː` all represent distinct morphemes, and where further combinations such as high-pitched plus intensified plus long `a` produce additional semantic contrasts. In such a language, the yinyuan system would no longer reduce to a traditional phonemic system, but would appear as a theoretically maximally expanded yinyuan system.

To my knowledge, no known natural language has yet been clearly demonstrated to use pitch, intensity, quality, and duration all as fully systematic and coequal distinctive features. For that reason, this case is best understood, at present, as a theoretical maximal model.

### The position of Modern Standard Chinese

Modern Standard Chinese may be understood as a special case within this broader framework.

In Modern Standard Chinese, generally speaking:

1. pitch and quality are the principal distinctive features,
2. while intensity and duration do not normally function as primary differentiators of morphemic meaning.

For this reason, the Yinyuan system of Chinese may be provisionally described as a special case of the broader framework, namely one in which pitch and quality are the principal contrastive features, while intensity and duration remain part of the more general theoretical horizon.

## Relation to the Traditional Phonemic System

The difference between the Yinyuan system and the traditional phonemic system is especially visible in tonal languages.

The traditional phonemic system typically:

1. segments speech mainly by quality, and
2. treats tone as either an accessory feature of the syllable or as something to be analyzed separately.

The Yinyuan system instead:

1. when required by the language, segments speech jointly by contrastive properties such as pitch and quality,
2. includes consonantal noise in the same formal system, except that its pitch value is taken as zero or null,
3. does not treat tone merely as an accessory feature of the whole syllable, and
4. does not externalize tone as an independent tier.

In non-tonal languages, however, where semantic contrast is carried by quality alone, the Yinyuan system may reduce to the traditional phonemic system. In that sense:

1. the two systems may yield equivalent analyses in such languages, and
2. the Yinyuan system should be understood as a more general analytic framework, of which the phonemic system can be a special case.

## Recommended Usage

In Chinese prose, it is advisable to keep the original terms:

- 时段
- 片音
- 音元

In English prose, the first occurrence is best written as:

- temporal slot,
- pianyin (phonic slice),
- yinyuan.

If the discussion is explicitly limited to Modern Standard Chinese, the first occurrence may instead be written as:

- yinyuan (a pitch-quality slot unit in the Modern Standard Chinese case).

After the terms have been defined, shorter usage is acceptable when the context is clear:

- slot,
- pianyin,
- yinyuan.

This preserves terminological stability while avoiding the false impression that the Yinyuan system is merely a relabeling of standard phonemic terminology.

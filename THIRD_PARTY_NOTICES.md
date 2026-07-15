# Third-party notices

This document identifies the principal third-party works included in or used
to build Yime. It supplements, and does not replace, the original notices and
license files. Copyright remains with the respective authors and contributors.

## EasyIME/PIME

- Upstream: https://github.com/EasyIME/PIME
- Principal original author: Hong Jen-Yee (PCMan)
- Role: Windows TSF host, launcher lineage, backend protocol, installer and
  registration infrastructure
- License: GNU Library General Public License version 2 or later
  (`LGPL-2.0-or-later`) according to inherited file-level notices
- Files: `LGPL-2.0.txt`, `LICENSES/PIME-UPSTREAM-LICENSE.txt`, `AUTHORS.txt`

Yime contains modified PIME code. It is not an official PIME release, and the
upstream authors are not responsible for Yime-specific changes.

## EasyIME/libIME2

- Upstream: https://github.com/EasyIME/libIME2
- Yime-maintained fork: https://github.com/tsaanghwang/libIME2
- Role: C++ wrapper around Windows Text Services Framework
- License: GNU Lesser General Public License version 2.1
- Authoritative notice: the `libIME2` submodule's `LICENSE.txt`

## librime

- Upstream: https://github.com/rime/librime
- Role: Rime input-method engine distributed as `rime.dll` and related tools
- License: BSD 3-Clause
- Full text: `LICENSES/RIME-BSD-3-Clause.txt`

Neither the RIME copyright holder nor its contributors endorse Yime.

## rime-frost and Rime shared data

- Upstream: https://github.com/gaboolic/rime-frost
- Role: preset Rime schemas, dictionaries, shared data, and data used as build
  inputs for the packaged runtime
- License: GNU General Public License version 3
- Full text: `LICENSES/RIME-FROST-GPL-3.0.txt`

The Yime build may also merge shared data installed by Rime Plum or Weasel.
Those files retain their own upstream notices. Release builders must not strip
license files or represent third-party data as exclusively authored by Yime.

## YinYuan font / Source Han Sans

`YinYuan-Regular.ttf` contains modified Source Han Sans font software.

- Original font copyright: Copyright 2014-2025 Adobe
- Upstream: https://github.com/adobe-fonts/source-han-sans
- License: SIL Open Font License version 1.1
- Reserved Font Name: `Source`
- Full text: `LICENSES/SIL-OFL-1.1.txt`

The modified font uses the name `YinYuan`, not Adobe's Reserved Font Name.
Adobe and the Source Han Sans contributors do not endorse Yime.

## Unicode Unihan data

- Upstream: https://www.unicode.org/Public/UNIDATA/Unihan.zip
- Role: source readings used to derive Yime pinyin normalization and reading
  tables
- Copyright: Copyright (C) 1991-present Unicode, Inc.
- License: Unicode License version 3 (`Unicode-3.0`)
- Full text: `LICENSES/UNICODE-3.0.txt`

Generated Yime tables do not imply endorsement by Unicode, Inc.

## BCC corpus frequency statistics

- Source: BCC Corpus, Beijing Language and Culture University
- Website: https://bcc.blcu.edu.cn/
- Role: downloadable character and word-frequency statistics used as numeric
  weighting inputs; the raw BCC corpus text is not included in Yime
- Requested attribution: Xun Endong, Rao Gaoqi, Xiao Xiaoyue and Zang Jiaojiao,
  "The Construction of the BCC Corpus in the Age of Big Data," Corpus
  Linguistics, 2016, Vol. 3, No. 1

BCC's help page permits free use of downloadable frequency statistics and asks
users to cite the BCC paper. This notice records that source and citation; it
does not claim ownership of BCC material.

## nlohmann/json

- Upstream: https://github.com/nlohmann/json
- Role: JSON parsing in the native TSF host
- License: MIT
- Full text and copyright notice: `json/LICENSE.MIT`

## Rust dependencies

PIMELauncher statically includes Rust crates resolved by
`PIMELauncher/Cargo.lock`. Package names, versions, declared SPDX expressions,
and upstream links are recorded in `LICENSES/RUST-DEPENDENCIES.md`. The
corresponding package-specific notices remain authoritative.

## NSIS plug-ins

The installer includes the INetC and md5dll NSIS plug-ins. Their corresponding
source and notices are retained under `installer/inetc` and `installer/md5dll`.
Only the x86 Unicode plug-in binaries used by the YIME installer are retained;
examples and unused binary variants are not part of this repository.

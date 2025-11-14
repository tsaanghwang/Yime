## 引言

音元输入法是通过输入表示音元的字符输入每个带声调的音节从而输入与每个带声调的音节对应的汉字和语句的音码输入法。音元输入法的码元就是音元系统的音元。音元系统是根据音元分析法构建的语音系统。在现代通用汉语中，音元共有52个：充当首音的噪音22个；构成干音的乐音30个。首音亦即噪音对应《汉语拼音方案》的声母。首音分成实首音和虚首音两类。实首音对应非零声母。虚首音对应零声母。干音由乐音构成，对应《汉语拼音方案》的带调韵母。乐音分成高调乐音、中调乐音和低调乐音三类，每类10个。乐音与《汉语拼音方案》的音质音位和声调音位没有简单而又直接的对应关系。在音元系统中，表示音元的字符也简称为音符。音元输入法是平均码长最短的全拼输入法，且有与全拼对应的合符音理的简拼、双拼和并击输入法。并击，也称合击，是指同时触碰或按压一组表示干音或音节的音符对应的键位输入干音或音节。

## 码元

音元系统的音元就是音元输入法的码元。全拼原则上是一音一码。

1.  
2.  

### 音元输入法的键盘布局

根据一音一码原则，音元输入法可用两种键盘输入汉字：一种是设计新式键盘。这种键盘的布局是，通过调用中英文切换键改变输入状态，在中文输入状态下，把美式键盘的大小写字母键全部做成下档键并重新排布键位。这就是说，这种键盘共有52个下档键位：键值为65~90和97~122的键位；其它键值的键位，包括数字0~9、运算符号、标点符号、等等，全部做成上档键位。这种键盘主要用来根据音元输入法输入汉字。

在这种键盘上，音元的分布草图如图：

图 1音元在键盘上的分布

一种是采用重新排布键位的美式键盘。在全拼状态下，按照一音一码的原则要求，47个音元对应的音符排布在初始状态下，5个音元对应的音符排布在shift（上档）状态下。在这种键盘上，音元的分布草图如图：

<figure>
<img src="images/media/image1.jpg"
style="width:7.08681in;height:3.06944in"
alt="图形用户界面, 文本, 应用程序 AI 生成的内容可能不正确。" />
<figcaption><p>图 2音元在键盘上的分布</p></figcaption>
</figure>

<figure>
<img src="images/media/image2.jpg"
style="width:7.08681in;height:3.06944in"
alt="图示 AI 生成的内容可能不正确。" />
<figcaption><p>图 3音元在键盘上的分布</p></figcaption>
</figure>

### 音元与键位的对应关系

在音元输入法中，根据一音一码原则确定音元与键位的对应关系。在现代通用汉语中，噪音就是首音。首音与《汉语拼音方案》的声母一一对应。首音ng\[ŋ\]对应部分或全部开口呼零声母或隔音符号，在美式键盘上，用小写字母键v键或其它字母键输入，以便做到完全不用符号键输入音元。

在音元输入法中，若仍用ascii码编码，以音元为线索，在美式键盘上，音元对应的键位——首音和乐音对应的键位列表见表：

<table style="width:100%;">
<caption><p>表 1音元对应的键位</p></caption>
<colgroup>
<col style="width: 8%" />
<col style="width: 8%" />
<col style="width: 8%" />
<col style="width: 8%" />
<col style="width: 8%" />
<col style="width: 8%" />
<col style="width: 8%" />
<col style="width: 7%" />
<col style="width: 8%" />
<col style="width: 7%" />
<col style="width: 8%" />
<col style="width: 6%" />
</colgroup>
<thead>
<tr>
<th colspan="6" style="text-align: center;">首音</th>
<th colspan="6" style="text-align: center;">乐音</th>
</tr>
</thead>
<tbody>
<tr>
<td style="text-align: center;">首音</td>
<td style="text-align: center;">键位</td>
<td style="text-align: center;">首音</td>
<td style="text-align: center;">键位</td>
<td style="text-align: center;">首音</td>
<td style="text-align: center;">键位</td>
<td style="text-align: center;">高调乐音</td>
<td style="text-align: center;">键位</td>
<td style="text-align: center;">中调乐音</td>
<td style="text-align: center;">键位</td>
<td style="text-align: center;">低调乐音</td>
<td style="text-align: center;">键位</td>
</tr>
<tr>
<td style="text-align: center;">下唇首音</td>
<td style="text-align: center;">下唇声母</td>
<td style="text-align: center;">齿龈首音</td>
<td style="text-align: center;">齿龈声母</td>
<td style="text-align: center;">软腭首音</td>
<td style="text-align: center;">软腭声母</td>
<td style="text-align: center;">󰌾</td>
<td style="text-align: center;">A</td>
<td style="text-align: center;">󰌿</td>
<td style="text-align: center;">R</td>
<td style="text-align: center;">󰍂</td>
<td style="text-align: center;">a</td>
</tr>
<tr>
<td style="text-align: center;">b</td>
<td style="text-align: center;">b</td>
<td style="text-align: center;">d</td>
<td style="text-align: center;">d</td>
<td style="text-align: center;">g</td>
<td style="text-align: center;">g</td>
<td style="text-align: center;">󰍒</td>
<td style="text-align: center;">O</td>
<td style="text-align: center;">󰍓</td>
<td style="text-align: center;">X</td>
<td style="text-align: center;">󰍖</td>
<td style="text-align: center;">o</td>
</tr>
<tr>
<td style="text-align: center;">p</td>
<td style="text-align: center;">p</td>
<td style="text-align: center;">t</td>
<td style="text-align: center;">t</td>
<td style="text-align: center;">k</td>
<td style="text-align: center;">k</td>
<td style="text-align: center;">󰍡</td>
<td style="text-align: center;">E</td>
<td style="text-align: center;">󰍢</td>
<td style="text-align: center;">F</td>
<td style="text-align: center;">󰍥</td>
<td style="text-align: center;">e</td>
</tr>
<tr>
<td style="text-align: center;">f</td>
<td style="text-align: center;">f</td>
<td style="text-align: center;">l</td>
<td style="text-align: center;">l</td>
<td style="text-align: center;">h</td>
<td style="text-align: center;">h</td>
<td style="text-align: center;">í</td>
<td style="text-align: center;">I</td>
<td style="text-align: center;">ī</td>
<td style="text-align: center;">J</td>
<td style="text-align: center;">ì</td>
<td style="text-align: center;">i</td>
</tr>
<tr>
<td style="text-align: center;">m</td>
<td style="text-align: center;">m</td>
<td style="text-align: center;">n</td>
<td style="text-align: center;">n</td>
<td style="text-align: center;">ŋ(ng)</td>
<td style="text-align: center;">v</td>
<td style="text-align: center;">ú</td>
<td style="text-align: center;">U</td>
<td style="text-align: center;">ū</td>
<td style="text-align: center;">W</td>
<td style="text-align: center;">ù</td>
<td style="text-align: center;">u</td>
</tr>
<tr>
<td style="text-align: center;">齿背首音</td>
<td style="text-align: center;">齿背声母</td>
<td style="text-align: center;">龈后首音</td>
<td style="text-align: center;">龈后声母</td>
<td style="text-align: center;">硬腭首音</td>
<td style="text-align: center;">硬腭声母</td>
<td style="text-align: center;">󰌴</td>
<td style="text-align: center;">Y</td>
<td style="text-align: center;">󰌵</td>
<td style="text-align: center;">V</td>
<td style="text-align: center;">󰌸</td>
<td style="text-align: center;">y</td>
</tr>
<tr>
<td style="text-align: center;">z</td>
<td style="text-align: center;">z</td>
<td style="text-align: center;">ẑ(zh)</td>
<td style="text-align: center;">Z</td>
<td style="text-align: center;">j</td>
<td style="text-align: center;">j</td>
<td style="text-align: center;">󰍵</td>
<td style="text-align: center;">L</td>
<td style="text-align: center;">󰍶</td>
<td style="text-align: center;">Q</td>
<td style="text-align: center;">󰍹</td>
<td style="text-align: center;">w</td>
</tr>
<tr>
<td style="text-align: center;">c</td>
<td style="text-align: center;">c</td>
<td style="text-align: center;">ĉ(ch)</td>
<td style="text-align: center;">C</td>
<td style="text-align: center;">q</td>
<td style="text-align: center;">q</td>
<td style="text-align: center;">󰎄</td>
<td style="text-align: center;">B</td>
<td style="text-align: center;">󰎅</td>
<td style="text-align: center;">P</td>
<td style="text-align: center;">󰎈</td>
<td style="text-align: center;">M</td>
</tr>
<tr>
<td style="text-align: center;">s</td>
<td style="text-align: center;">s</td>
<td style="text-align: center;">ŝ(sh)</td>
<td style="text-align: center;">S</td>
<td style="text-align: center;">x</td>
<td style="text-align: center;">x</td>
<td style="text-align: center;">ń</td>
<td style="text-align: center;">D</td>
<td style="text-align: center;">󰎔</td>
<td style="text-align: center;">T</td>
<td style="text-align: center;">ǹ</td>
<td style="text-align: center;">N</td>
</tr>
<tr>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">r</td>
<td style="text-align: center;">r</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰎘</td>
<td style="text-align: center;">G</td>
<td style="text-align: center;">󰎙</td>
<td style="text-align: center;">K</td>
<td style="text-align: center;">󰎜</td>
<td style="text-align: center;">H</td>
</tr>
<tr>
<td rowspan="2" style="text-align: center;">首音7</td>
<td rowspan="2" style="text-align: center;">小写7</td>
<td rowspan="2" style="text-align: center;">首音8</td>
<td style="text-align: center;">大写3</td>
<td rowspan="2" style="text-align: center;">首音7</td>
<td rowspan="2" style="text-align: center;">小写7</td>
<td rowspan="2" style="text-align: center;">10</td>
<td rowspan="2" style="text-align: center;">大写10</td>
<td rowspan="2" style="text-align: center;">10</td>
<td rowspan="2" style="text-align: center;">大写10</td>
<td rowspan="2" style="text-align: center;">10</td>
<td style="text-align: center;">大写3</td>
</tr>
<tr>
<td style="text-align: center;">小写5</td>
<td style="text-align: center;">小写7</td>
</tr>
<tr>
<td colspan="6" style="text-align: center;">小写19+大写3=首音22</td>
<td colspan="6" style="text-align: center;">大写23+小写7=乐音30</td>
</tr>
<tr>
<td colspan="12" style="text-align: center;">键位52=音元52</td>
</tr>
</tbody>
</table>

在音元输入法中，若仍用ascii码给机器编码，以键位为线索，在美式键盘上，键位对应的音元——大写和小写键位对应的音元列表见表：

<table style="width:75%;">
<caption><p>表 2键位对应的音元</p></caption>
<colgroup>
<col style="width: 6%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 2%" />
<col style="width: 2%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 4%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 3%" />
</colgroup>
<thead>
<tr>
<th style="text-align: center;">档位</th>
<th colspan="10" style="text-align: center;">小写</th>
<th colspan="10" style="text-align: center;">大写</th>
</tr>
</thead>
<tbody>
<tr>
<td style="text-align: center;">键位</td>
<td style="text-align: center;">a</td>
<td style="text-align: center;">b</td>
<td style="text-align: center;">c</td>
<td style="text-align: center;">d</td>
<td style="text-align: center;">e</td>
<td style="text-align: center;">f</td>
<td style="text-align: center;">g</td>
<td style="text-align: center;">h</td>
<td style="text-align: center;">i</td>
<td style="text-align: center;">j</td>
<td style="text-align: center;">A</td>
<td style="text-align: center;">B</td>
<td style="text-align: center;">C</td>
<td style="text-align: center;">D</td>
<td style="text-align: center;">E</td>
<td style="text-align: center;">F</td>
<td style="text-align: center;">G</td>
<td style="text-align: center;">H</td>
<td style="text-align: center;">I</td>
<td style="text-align: center;">J</td>
</tr>
<tr>
<td style="text-align: center;">音元</td>
<td style="text-align: center;">󰍂</td>
<td style="text-align: center;">b</td>
<td style="text-align: center;">c</td>
<td style="text-align: center;">d</td>
<td style="text-align: center;">󰍥</td>
<td style="text-align: center;">f</td>
<td style="text-align: center;">g</td>
<td style="text-align: center;">h</td>
<td style="text-align: center;">ì</td>
<td style="text-align: center;">j</td>
<td style="text-align: center;">󰌾</td>
<td style="text-align: center;">󰎄</td>
<td style="text-align: center;">ĉ</td>
<td style="text-align: center;">ń</td>
<td style="text-align: center;">󰍡</td>
<td style="text-align: center;">󰍢</td>
<td style="text-align: center;">󰎘</td>
<td style="text-align: center;">󰎜</td>
<td style="text-align: center;">í</td>
<td style="text-align: center;">ī</td>
</tr>
<tr>
<td style="text-align: center;">键位</td>
<td style="text-align: center;">k</td>
<td style="text-align: center;">l</td>
<td style="text-align: center;">m</td>
<td style="text-align: center;">n</td>
<td style="text-align: center;">o</td>
<td style="text-align: center;">p</td>
<td style="text-align: center;">q</td>
<td style="text-align: center;">r</td>
<td style="text-align: center;">s</td>
<td style="text-align: center;">t</td>
<td style="text-align: center;">K</td>
<td style="text-align: center;">L</td>
<td style="text-align: center;">M</td>
<td style="text-align: center;">N</td>
<td style="text-align: center;">O</td>
<td style="text-align: center;">P</td>
<td style="text-align: center;">Q</td>
<td style="text-align: center;">R</td>
<td style="text-align: center;">S</td>
<td style="text-align: center;">T</td>
</tr>
<tr>
<td style="text-align: center;">音元</td>
<td style="text-align: center;">k</td>
<td style="text-align: center;">l</td>
<td style="text-align: center;">m</td>
<td style="text-align: center;">n</td>
<td style="text-align: center;">󰍖</td>
<td style="text-align: center;">p</td>
<td style="text-align: center;">q</td>
<td style="text-align: center;">r</td>
<td style="text-align: center;">s</td>
<td style="text-align: center;">t</td>
<td style="text-align: center;">󰎙</td>
<td style="text-align: center;">󰍵</td>
<td style="text-align: center;">󰎈</td>
<td style="text-align: center;">ǹ</td>
<td style="text-align: center;">󰍒</td>
<td style="text-align: center;">󰎅</td>
<td style="text-align: center;">󰍶</td>
<td style="text-align: center;">󰌿</td>
<td style="text-align: center;">ŝ</td>
<td style="text-align: center;">󰎔</td>
</tr>
<tr>
<td style="text-align: center;">键位</td>
<td style="text-align: center;">u</td>
<td style="text-align: center;">v</td>
<td style="text-align: center;">w</td>
<td style="text-align: center;">x</td>
<td style="text-align: center;">y</td>
<td style="text-align: center;">z</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">U</td>
<td style="text-align: center;">V</td>
<td style="text-align: center;">W</td>
<td style="text-align: center;">X</td>
<td style="text-align: center;">Y</td>
<td style="text-align: center;">Z</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">音元</td>
<td style="text-align: center;">ù</td>
<td style="text-align: center;">ŋ</td>
<td style="text-align: center;">󰍹</td>
<td style="text-align: center;">x</td>
<td style="text-align: center;">󰌸</td>
<td style="text-align: center;">z</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">ú</td>
<td style="text-align: center;">󰌵</td>
<td style="text-align: center;">ū</td>
<td style="text-align: center;">󰍓</td>
<td style="text-align: center;">󰌴</td>
<td style="text-align: center;">ẑ</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">合计</td>
<td colspan="10" style="text-align: center;">19+7=26</td>
<td colspan="10" style="text-align: center;">23+3=26</td>
</tr>
</tbody>
</table>

在新式键盘上，若仍用ascii码给机器编码，音元与键位的对应关系如图：

音元与键位在美式键盘上的对应关系参考上图修改。

### 音元与音符的对应关系

在音元输入法中，根据一音一符原则确定确定音元与音符（表示音元的字符）的对应关系。在音元系统中，为与中文或英文混排，表示音元，需要用到三套字符：与中文兼容的全宽字符、与中文兼容的半宽字符和与英文兼容的比例字符。

在音元输入法中，音元对应的音符——首音和乐音，用与中文兼容的全宽字符和与英文兼容的半宽字符来记音，列表见表：

| 全宽音符 |   󰄠   |   󰄡    |   󰄢   |   󰄣   |   󰄤   |   󰄥   |   󰄦    |   󰄧   |   󰄨   |
|:--------:|:-----:|:------:|:-----:|:-----:|:-----:|:-----:|:------:|:-----:|:-----:|
| 半宽音符 |   󰃐   |   󰃑    |   󰃒   |   󰃓   |   󰃔   |   󰃕   |   󰃖    |   󰃗   |   󰃘   |
|   音元   |   p   |   pʰ   |   f   |   m   |   w   |   ʦ   |   ʦʰ   |   s   |   ɹ   |
|   音标   | \[p\] | \[pʰ\] | \[f\] | \[m\] | \[w\] | \[ʦ\] | \[ʦʰ\] | \[s\] | \[ɹ\] |
| 拼音方案 |   b   |   p    |   f   |   m   |   w   |   z   |   c    |   s   |       |
| 全宽音符 |   󰄩   |   󰄪    |   󰄫   |   󰄬   |   󰄭   |   󰄷   |   󰄸    |   󰄹   |   󰄺   |
| 半宽音符 |   󰃙   |   󰃚    |   󰃛   |   󰃜   |   󰃝   |   󰃧   |   󰃨    |   󰃩   |   󰃪   |
|   音元   |   t   |   tʰ   |   l   |   n   |   j   |   ꭧ   |   ꭧʰ   |   ʂ   |   ɻ   |
|   音标   | \[t\] | \[tʰ\] | \[l\] | \[n\] | \[j\] | \[ꭧ\] | \[ꭧʰ\] | \[ʂ\] | \[ɻ\] |
| 拼音方案 |   d   |   t    |   l   |   n   |   y   |   ẑ   |   ĉ    |   ŝ   |   r   |
| 全宽音符 |   󰄲   |   󰄳    |   󰄴   |   󰄵   |   󰄶   |   󰄮   |   󰄯    |   󰄰   |   󰄱   |
| 半宽音符 |   󰃢   |   󰃣    |   󰃤   |   󰃥   |   󰃦   |   󰃞   |   󰃟    |   󰃠   |   󰃡   |
|   音元   |   k   |   kʰ   |   x   |   ŋ   |   ɣ   |   ʨ   |   ʨʰ   |   ɕ   |   ɥ   |
|   音标   | \[k\] | \[kʰ\] | \[x\] | \[ŋ\] | \[ɣ\] | \[ʨ\] | \[ʨʰ\] | \[ɕ\] | \[ɥ\] |
| 拼音方案 |   g   |   k    |   h   |       |   '   |   j   |   q    |   x   |   y   |

表 3首音的音符

<table style="width:63%;">
<caption><p>表 4乐音的音符</p></caption>
<colgroup>
<col style="width: 6%" />
<col style="width: 10%" />
<col style="width: 4%" />
<col style="width: 4%" />
<col style="width: 4%" />
<col style="width: 4%" />
<col style="width: 4%" />
<col style="width: 4%" />
<col style="width: 4%" />
<col style="width: 4%" />
<col style="width: 4%" />
<col style="width: 4%" />
</colgroup>
<tbody>
<tr>
<td rowspan="4" style="text-align: center;">高调</td>
<td style="text-align: center;">全宽音符</td>
<td style="text-align: center;">󰊰</td>
<td style="text-align: center;">󰊳</td>
<td style="text-align: center;">󰊶</td>
<td style="text-align: center;">󰊹</td>
<td style="text-align: center;">󰊼</td>
<td style="text-align: center;">󰊿</td>
<td style="text-align: center;">󰋂</td>
<td style="text-align: center;">󰋅</td>
<td style="text-align: center;">󰋈</td>
<td style="text-align: center;">󰋋</td>
</tr>
<tr>
<td style="text-align: center;">半宽音符</td>
<td style="text-align: center;">󰃰</td>
<td style="text-align: center;">󰃳</td>
<td style="text-align: center;">󰃶</td>
<td style="text-align: center;">󰃹</td>
<td style="text-align: center;">󰃼</td>
<td style="text-align: center;">󰃿</td>
<td style="text-align: center;">󰄂</td>
<td style="text-align: center;">󰄅</td>
<td style="text-align: center;">󰄈</td>
<td style="text-align: center;">󰄋</td>
</tr>
<tr>
<td style="text-align: center;">音元</td>
<td style="text-align: center;">󰌠</td>
<td style="text-align: center;">󰌪</td>
<td style="text-align: center;">󰌴</td>
<td style="text-align: center;">󰌾</td>
<td style="text-align: center;">󰍒</td>
<td style="text-align: center;">󰍡</td>
<td style="text-align: center;">󰍵</td>
<td style="text-align: center;">󰎄</td>
<td style="text-align: center;">󰎓</td>
<td style="text-align: center;">󰎘</td>
</tr>
<tr>
<td style="text-align: center;">音标</td>
<td style="text-align: center;">[󰌠]</td>
<td style="text-align: center;">[󰌪]</td>
<td style="text-align: center;">[󰌴]</td>
<td style="text-align: center;">[󰌾]</td>
<td style="text-align: center;">[󰍒]</td>
<td style="text-align: center;">[󰍡]</td>
<td style="text-align: center;">[󰍿]</td>
<td style="text-align: center;">[󰎘]</td>
<td style="text-align: center;">[󰎓]</td>
<td style="text-align: center;">[󰎘]</td>
</tr>
<tr>
<td rowspan="4" style="text-align: center;">中调</td>
<td style="text-align: center;">全宽音符</td>
<td style="text-align: center;">󰊱</td>
<td style="text-align: center;">󰊴</td>
<td style="text-align: center;">󰊷</td>
<td style="text-align: center;">󰊺</td>
<td style="text-align: center;">󰊽</td>
<td style="text-align: center;">󰋀</td>
<td style="text-align: center;">󰋃</td>
<td style="text-align: center;">󰋆</td>
<td style="text-align: center;">󰋉</td>
<td style="text-align: center;">󰋌</td>
</tr>
<tr>
<td style="text-align: center;">半宽音符</td>
<td style="text-align: center;">󰃱</td>
<td style="text-align: center;">󰃴</td>
<td style="text-align: center;">󰃷</td>
<td style="text-align: center;">󰃺</td>
<td style="text-align: center;">󰃽</td>
<td style="text-align: center;">󰄀</td>
<td style="text-align: center;">󰄃</td>
<td style="text-align: center;">󰄆</td>
<td style="text-align: center;">󰄉</td>
<td style="text-align: center;">󰄌</td>
</tr>
<tr>
<td style="text-align: center;">音元</td>
<td style="text-align: center;">󰌡</td>
<td style="text-align: center;">󰌫</td>
<td style="text-align: center;">󰌵</td>
<td style="text-align: center;">󰌿</td>
<td style="text-align: center;">󰍓</td>
<td style="text-align: center;">󰍢</td>
<td style="text-align: center;">󰍶</td>
<td style="text-align: center;">󰎔</td>
<td style="text-align: center;">󰎔</td>
<td style="text-align: center;">󰎙</td>
</tr>
<tr>
<td style="text-align: center;">音标</td>
<td style="text-align: center;">[󰌡]</td>
<td style="text-align: center;">[󰌫]</td>
<td style="text-align: center;">[󰌵]</td>
<td style="text-align: center;">[󰌿]</td>
<td style="text-align: center;">[󰍓]</td>
<td style="text-align: center;">[󰍢]</td>
<td style="text-align: center;">[󰎀]</td>
<td style="text-align: center;">[󰎙]</td>
<td style="text-align: center;">[󰎔]</td>
<td style="text-align: center;">[󰎙]</td>
</tr>
<tr>
<td rowspan="4" style="text-align: center;">低调</td>
<td style="text-align: center;">全宽音符</td>
<td style="text-align: center;">󰊲</td>
<td style="text-align: center;">󰊵</td>
<td style="text-align: center;">󰊸</td>
<td style="text-align: center;">󰊻</td>
<td style="text-align: center;">󰊾</td>
<td style="text-align: center;">󰋁</td>
<td style="text-align: center;">󰋄</td>
<td style="text-align: center;">󰋇</td>
<td style="text-align: center;">󰋊</td>
<td style="text-align: center;">󰋍</td>
</tr>
<tr>
<td style="text-align: center;">半宽音符</td>
<td style="text-align: center;">󰃲</td>
<td style="text-align: center;">󰃵</td>
<td style="text-align: center;">󰃸</td>
<td style="text-align: center;">󰃻</td>
<td style="text-align: center;">󰃾</td>
<td style="text-align: center;">󰄁</td>
<td style="text-align: center;">󰄄</td>
<td style="text-align: center;">󰄇</td>
<td style="text-align: center;">󰄊</td>
<td style="text-align: center;">󰄍</td>
</tr>
<tr>
<td style="text-align: center;">音元</td>
<td style="text-align: center;">󰌤</td>
<td style="text-align: center;">󰌮</td>
<td style="text-align: center;">󰌸</td>
<td style="text-align: center;">󰍂</td>
<td style="text-align: center;">󰍖</td>
<td style="text-align: center;">󰍥</td>
<td style="text-align: center;">󰍹</td>
<td style="text-align: center;">󰎈</td>
<td style="text-align: center;">󰎗</td>
<td style="text-align: center;">󰎜</td>
</tr>
<tr>
<td style="text-align: center;">音标</td>
<td style="text-align: center;">[󰌤]</td>
<td style="text-align: center;">[󰌮]</td>
<td style="text-align: center;">[󰌸]</td>
<td style="text-align: center;">[󰍂]</td>
<td style="text-align: center;">[󰍖]</td>
<td style="text-align: center;">[󰍥]</td>
<td style="text-align: center;">[󰎃]</td>
<td style="text-align: center;">[󰎜]</td>
<td style="text-align: center;">[󰎗]</td>
<td style="text-align: center;">[󰎜]</td>
</tr>
</tbody>
</table>

这套字符只是临时的试样，在使用过程中，可根据社会认可度修改。

## 干音

根据音元分析法标记干音，既可采用与汉字兼容的字符标音也可采用与英文兼容的字符标音。用与汉字兼容的字符来标音就是，首先把标记干音的三个音元的音符竖向排成一列，然后，或把这列字符制作成一个高度占居一个汉字高度、宽度占居半个汉字宽度的标记干音的半宽字符，或把这列字符制作成一个高度占居一个汉字高度、宽度占居一个汉字宽度的标记干音的全宽字符。半宽字符在首音和干音拼合成音节时使用。全宽字符在首音或干音游离在行文中时使用。干音分成二音和韵音两段。干音根据韵音的音质也就是说韵质是否相近或相同分成十八类：󰅀类干音、󰅄类干音、󰅈类干音、󰅌类干音、󰅘类干音、󰅨类干音、󰅸类干音、󰅼类干音、󰆄类干音、󰆈类干音、󰆌类干音、󰆔类干音、󰆜类干音、󰆤类干音、󰆬类干音、󰆼类干音、󰇌类干音和󰇘类干音。

干音根据韵质分类采用与汉字兼容的字符标音详见。

<table style="width:61%;">
<caption><p>表 5干音用半宽字符来标音</p></caption>
<colgroup>
<col style="width: 9%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 3%" />
</colgroup>
<tbody>
<tr>
<td style="text-align: center;">节调类型</td>
<td colspan="4" style="text-align: center;">高调阴平</td>
<td colspan="4" style="text-align: center;">升调阳平</td>
<td colspan="4" style="text-align: center;">低调上声</td>
<td colspan="4" style="text-align: center;">降调去声</td>
</tr>
<tr>
<td style="text-align: center;">二音类型</td>
<td style="text-align: center;">未</td>
<td style="text-align: center;">噫</td>
<td style="text-align: center;">呜</td>
<td style="text-align: center;">吁</td>
<td style="text-align: center;">未</td>
<td style="text-align: center;">噫</td>
<td style="text-align: center;">呜</td>
<td style="text-align: center;">吁</td>
<td style="text-align: center;">未</td>
<td style="text-align: center;">噫</td>
<td style="text-align: center;">呜</td>
<td style="text-align: center;">吁</td>
<td style="text-align: center;">未</td>
<td style="text-align: center;">噫</td>
<td style="text-align: center;">呜</td>
<td style="text-align: center;">吁</td>
</tr>
<tr>
<td style="text-align: center;">󰅀类干音</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰀠</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰀡</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰀢</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰀣</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">󰅄类干音</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰀤</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰀥</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰀦</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰀧</td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">󰅈类干音</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰀨</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰀩</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰀪</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰀫</td>
</tr>
<tr>
<td style="text-align: center;">󰅌类干音</td>
<td style="text-align: center;">󰀬</td>
<td style="text-align: center;">󰀰</td>
<td style="text-align: center;">󰀴</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰀭</td>
<td style="text-align: center;">󰀱</td>
<td style="text-align: center;">󰀵</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰀮</td>
<td style="text-align: center;">󰀲</td>
<td style="text-align: center;">󰀶</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰀯</td>
<td style="text-align: center;">󰀳</td>
<td style="text-align: center;">󰀷</td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">󰅘类干音</td>
<td style="text-align: center;">󰀸</td>
<td style="text-align: center;">󰀼</td>
<td style="text-align: center;">󰁀</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰀹</td>
<td style="text-align: center;">󰀽</td>
<td style="text-align: center;">󰁁</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰀺</td>
<td style="text-align: center;">󰀾</td>
<td style="text-align: center;">󰁂</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰀻</td>
<td style="text-align: center;">󰀿</td>
<td style="text-align: center;">󰁃</td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">󰅨类干音</td>
<td style="text-align: center;">󰁈</td>
<td style="text-align: center;">󰁌</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁐</td>
<td style="text-align: center;">󰁉</td>
<td style="text-align: center;">󰁍</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁑</td>
<td style="text-align: center;">󰁊</td>
<td style="text-align: center;">󰁎</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁒</td>
<td style="text-align: center;">󰁋</td>
<td style="text-align: center;">󰁏</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁓</td>
</tr>
<tr>
<td style="text-align: center;">󰅸类干音</td>
<td style="text-align: center;">󰁘</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁙</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁚</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁛</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">󰅼类干音</td>
<td style="text-align: center;">󰁜</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁝</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁞</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁟</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">󰆄类干音</td>
<td style="text-align: center;">󰁤</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁥</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁦</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁧</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">󰆈类干音</td>
<td style="text-align: center;">󰁨</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁩</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁪</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁫</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">󰆌类干音</td>
<td style="text-align: center;">󰁬</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁰</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁭</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁱</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁮</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁲</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁯</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁳</td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">󰆔类干音</td>
<td style="text-align: center;">󰁴</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁸</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁵</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁹</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁶</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁺</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁷</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁻</td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">󰆜类干音</td>
<td style="text-align: center;">󰁼</td>
<td style="text-align: center;">󰂀</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁽</td>
<td style="text-align: center;">󰂁</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁾</td>
<td style="text-align: center;">󰂂</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰁿</td>
<td style="text-align: center;">󰂃</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">󰆤类干音</td>
<td style="text-align: center;">󰂄</td>
<td style="text-align: center;">󰂈</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰂅</td>
<td style="text-align: center;">󰂉</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰂆</td>
<td style="text-align: center;">󰂊</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰂇</td>
<td style="text-align: center;">󰂋</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">󰆬类干音</td>
<td style="text-align: center;">󰂌</td>
<td style="text-align: center;">󰂐</td>
<td style="text-align: center;">󰂔</td>
<td style="text-align: center;">󰂘</td>
<td style="text-align: center;">󰂍</td>
<td style="text-align: center;">󰂑</td>
<td style="text-align: center;">󰂕</td>
<td style="text-align: center;">󰂙</td>
<td style="text-align: center;">󰂎</td>
<td style="text-align: center;">󰂒</td>
<td style="text-align: center;">󰂖</td>
<td style="text-align: center;">󰂚</td>
<td style="text-align: center;">󰂏</td>
<td style="text-align: center;">󰂓</td>
<td style="text-align: center;">󰂗</td>
<td style="text-align: center;">󰂛</td>
</tr>
<tr>
<td style="text-align: center;">󰆼类干音</td>
<td style="text-align: center;">󰂜</td>
<td style="text-align: center;">󰂠</td>
<td style="text-align: center;">󰂤</td>
<td style="text-align: center;">󰂨</td>
<td style="text-align: center;">󰂝</td>
<td style="text-align: center;">󰂡</td>
<td style="text-align: center;">󰂥</td>
<td style="text-align: center;">󰂩</td>
<td style="text-align: center;">󰂞</td>
<td style="text-align: center;">󰂢</td>
<td style="text-align: center;">󰂦</td>
<td style="text-align: center;">󰂪</td>
<td style="text-align: center;">󰂟</td>
<td style="text-align: center;">󰂣</td>
<td style="text-align: center;">󰂧</td>
<td style="text-align: center;">󰂫</td>
</tr>
<tr>
<td style="text-align: center;">󰇌类干音</td>
<td style="text-align: center;">󰂬</td>
<td style="text-align: center;">󰂰</td>
<td style="text-align: center;">󰂴</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰂭</td>
<td style="text-align: center;">󰂱</td>
<td style="text-align: center;">󰂵</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰂮</td>
<td style="text-align: center;">󰂲</td>
<td style="text-align: center;">󰂶</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰂯</td>
<td style="text-align: center;">󰂳</td>
<td style="text-align: center;">󰂷</td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">󰇘类干音</td>
<td style="text-align: center;">󰂸</td>
<td style="text-align: center;">󰂼</td>
<td style="text-align: center;">󰃀</td>
<td style="text-align: center;">󰃄</td>
<td style="text-align: center;">󰂹</td>
<td style="text-align: center;">󰂽</td>
<td style="text-align: center;">󰃁</td>
<td style="text-align: center;">󰃅</td>
<td style="text-align: center;">󰂺</td>
<td style="text-align: center;">󰂾</td>
<td style="text-align: center;">󰃂</td>
<td style="text-align: center;">󰃆</td>
<td style="text-align: center;">󰂻</td>
<td style="text-align: center;">󰂿</td>
<td style="text-align: center;">󰃃</td>
<td style="text-align: center;">󰃇</td>
</tr>
</tbody>
</table>

在本表中，音符丨在干音󰅁和󰅃中的写法由竖写变横写变成一。

在本表中，列标题“未”、“噫”、“呜”和“吁”依序是未名呼干音、齐齿呼干音、合口呼干音和撮口呼干音的简称。在音元系统中，根据二音的音质分类，干音分成未名呼干音、齐齿呼干音、合口呼干音和撮口呼干音四类。未名呼干音指除齐齿呼干音、合口呼干音和撮口呼干音外的干音。齐齿呼干音指二音是噫质二音的干音。合口呼干音指二音是呜质二音的干音。撮口呼干音指二音是吁质二音的干音。噫质二音指二音的音质是i\[i\]的二音。呜质二音指二音的音质是u\[u\]的二音。吁质二音指二音的音质是ʏ\[ʏ\]的二音。未名二音指除噫质二音、呜质二音和吁质二音外的二音。在根据韵音的音质的差异分类制表时，把未名呼干音、齐齿呼干音、合口呼干音和撮口呼干音各放在一列，把韵质相同的干音合放在一行。

用与英文兼容的字符来标音，就是把标记干音的三个音元的音符制作成三个高度占居半个汉字高度、宽度占居半个汉字宽度的半高半宽字符，并把标记干音的三个半高半宽字符依序在基线上横向排成一列标记干音的字符。

干音根据韵质分类采用与英文兼容的字符标音详见。

<table style="width:97%;">
<caption><p>表 6干音用字符序列来标音</p></caption>
<colgroup>
<col style="width: 10%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
</colgroup>
<tbody>
<tr>
<td style="text-align: center;">节调类型</td>
<td colspan="4" style="text-align: center;">高调阴平</td>
<td colspan="4" style="text-align: center;">升调阳平</td>
<td colspan="4" style="text-align: center;">低调上声</td>
<td colspan="4" style="text-align: center;">降调去声</td>
</tr>
<tr>
<td style="text-align: center;">二音类型</td>
<td style="text-align: center;">未</td>
<td style="text-align: center;">噫</td>
<td style="text-align: center;">呜</td>
<td style="text-align: center;">吁</td>
<td style="text-align: center;">未</td>
<td style="text-align: center;">噫</td>
<td style="text-align: center;">呜</td>
<td style="text-align: center;">吁</td>
<td style="text-align: center;">未</td>
<td style="text-align: center;">噫</td>
<td style="text-align: center;">呜</td>
<td style="text-align: center;">吁</td>
<td style="text-align: center;">未</td>
<td style="text-align: center;">噫</td>
<td style="text-align: center;">呜</td>
<td style="text-align: center;">吁</td>
</tr>
<tr>
<td style="text-align: center;">󰅀类干音</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃰󰃰󰃰</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃲󰃱󰃰</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃲󰃲󰃲</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃰󰃱󰃲</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">󰅄类干音</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃳󰃳󰃳</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃵󰃴󰃳</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃵󰃵󰃵</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃳󰃴󰃵</td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">󰅈类干音</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃶󰃶󰃶</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃸󰃷󰃶</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃸󰃸󰃸</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃶󰃷󰃸</td>
</tr>
<tr>
<td style="text-align: center;">󰅌类干音</td>
<td style="text-align: center;">󰃹󰃹󰃹</td>
<td style="text-align: center;">󰃰󰃹󰃹</td>
<td style="text-align: center;">󰃳󰃹󰃹</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃻󰃺󰃹</td>
<td style="text-align: center;">󰃲󰃺󰃹</td>
<td style="text-align: center;">󰃵󰃺󰃹</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃻󰃻󰃻</td>
<td style="text-align: center;">󰃲󰃻󰃻</td>
<td style="text-align: center;">󰃵󰃻󰃻</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃹󰃺󰃻</td>
<td style="text-align: center;">󰃰󰃺󰃻</td>
<td style="text-align: center;">󰃳󰃺󰃻</td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">󰅘类干音</td>
<td style="text-align: center;">󰃼󰃼󰃼</td>
<td style="text-align: center;">󰃰󰃼󰃼</td>
<td style="text-align: center;">󰃳󰃼󰃼</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃾󰃽󰃼</td>
<td style="text-align: center;">󰃲󰃽󰃼</td>
<td style="text-align: center;">󰃵󰃽󰃼</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃾󰃾󰃾</td>
<td style="text-align: center;">󰃲󰃾󰃾</td>
<td style="text-align: center;">󰃵󰃾󰃾</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃼󰃽󰃾</td>
<td style="text-align: center;">󰃰󰃽󰃾</td>
<td style="text-align: center;">󰃳󰃽󰃾</td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">󰅨类干音</td>
<td style="text-align: center;">󰃿󰃿󰃿</td>
<td style="text-align: center;">󰃰󰃿󰃿</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃶󰃿󰃿</td>
<td style="text-align: center;">󰄁󰄀󰃿</td>
<td style="text-align: center;">󰃲󰄀󰃿</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃸󰄀󰃿</td>
<td style="text-align: center;">󰄁󰄁󰄁</td>
<td style="text-align: center;">󰃲󰄁󰄁</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃸󰄁󰄁</td>
<td style="text-align: center;">󰃿󰄀󰄁</td>
<td style="text-align: center;">󰃰󰄀󰄁</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃶󰄀󰄁</td>
</tr>
<tr>
<td style="text-align: center;">󰅸类干音</td>
<td style="text-align: center;">󰄂󰄂󰄂</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰄄󰄃󰄂</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰄄󰄄󰄄</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰄂󰄃󰄄</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">󰅼类干音</td>
<td style="text-align: center;">󰄅󰄅󰄅</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰄇󰄆󰄅</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰄇󰄇󰄇</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰄅󰄆󰄇</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">󰆄类干音</td>
<td style="text-align: center;">󰄈󰄈󰄈</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰄊󰄉󰄈</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰄊󰄊󰄊</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰄈󰄉󰄊</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">󰆈类干音</td>
<td style="text-align: center;">󰄋󰄋󰄋</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰄍󰄌󰄋</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰄍󰄍󰄍</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰄋󰄌󰄍</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">󰆌类干音</td>
<td style="text-align: center;">󰃹󰃹󰃰</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃳󰃹󰃰</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃻󰃺󰃰</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃵󰃺󰃰</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃻󰃻󰃲</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃵󰃻󰃲</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃹󰃺󰃲</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃳󰃺󰃲</td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">󰆔类干音</td>
<td style="text-align: center;">󰃿󰃿󰃰</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃳󰃿󰃰</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰄁󰄀󰃰</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃵󰄀󰃰</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰄁󰄁󰃲</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃵󰄁󰃲</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃿󰄀󰃲</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃳󰄀󰃲</td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">󰆜类干音</td>
<td style="text-align: center;">󰃹󰃹󰃳</td>
<td style="text-align: center;">󰃰󰃹󰃳</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃻󰃺󰃳</td>
<td style="text-align: center;">󰃲󰃺󰃳</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃻󰃻󰃵</td>
<td style="text-align: center;">󰃲󰃻󰃵</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃹󰃺󰃵</td>
<td style="text-align: center;">󰃰󰃺󰃵</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">󰆤类干音</td>
<td style="text-align: center;">󰃼󰃼󰃳</td>
<td style="text-align: center;">󰃰󰃼󰃳</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃾󰃽󰃳</td>
<td style="text-align: center;">󰃲󰃽󰃳</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃾󰃾󰃵</td>
<td style="text-align: center;">󰃲󰃾󰃵</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃼󰃽󰃵</td>
<td style="text-align: center;">󰃰󰃽󰃵</td>
<td style="text-align: center;"></td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">󰆬类干音</td>
<td style="text-align: center;">󰃹󰃹󰄈</td>
<td style="text-align: center;">󰃰󰃹󰄈</td>
<td style="text-align: center;">󰃳󰃹󰄈</td>
<td style="text-align: center;">󰃶󰃹󰄈</td>
<td style="text-align: center;">󰃻󰃺󰄈</td>
<td style="text-align: center;">󰃲󰃺󰄈</td>
<td style="text-align: center;">󰃵󰃺󰄈</td>
<td style="text-align: center;">󰃸󰃺󰄈</td>
<td style="text-align: center;">󰃻󰃻󰄊</td>
<td style="text-align: center;">󰃲󰃻󰄊</td>
<td style="text-align: center;">󰃵󰃻󰄊</td>
<td style="text-align: center;">󰃸󰃻󰄊</td>
<td style="text-align: center;">󰃹󰃺󰄊</td>
<td style="text-align: center;">󰃰󰃺󰄊</td>
<td style="text-align: center;">󰃳󰃺</td>
<td style="text-align: center;">󰃶󰃺󰄊</td>
</tr>
<tr>
<td style="text-align: center;">󰆼类干音</td>
<td style="text-align: center;">󰃿󰃿󰄈</td>
<td style="text-align: center;">󰃰󰃿󰄈</td>
<td style="text-align: center;">󰃳󰃿󰄈</td>
<td style="text-align: center;">󰃶󰃿󰄈</td>
<td style="text-align: center;">󰄁󰄀󰄈</td>
<td style="text-align: center;">󰃲󰄀󰄈</td>
<td style="text-align: center;">󰃵󰄀󰄈</td>
<td style="text-align: center;">󰃸󰄀󰄈</td>
<td style="text-align: center;">󰄁󰄁󰄊</td>
<td style="text-align: center;">󰃲󰄁󰄊</td>
<td style="text-align: center;">󰃵󰄁󰄊</td>
<td style="text-align: center;">󰃸󰄁󰄊</td>
<td style="text-align: center;">󰃿󰄀󰄊</td>
<td style="text-align: center;">󰃰󰄀󰄊</td>
<td style="text-align: center;">󰃳󰄀󰄊</td>
<td style="text-align: center;">󰃶󰄀󰄊</td>
</tr>
<tr>
<td style="text-align: center;">󰇌类干音</td>
<td style="text-align: center;">󰃹󰃹󰄋</td>
<td style="text-align: center;">󰃰󰃹󰄋</td>
<td style="text-align: center;">󰃳󰃹󰄋</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃻󰃺󰄋</td>
<td style="text-align: center;">󰃲󰃺󰄋</td>
<td style="text-align: center;">󰃵󰃺󰄋</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃻󰃻󰄍</td>
<td style="text-align: center;">󰃲󰃻󰄍</td>
<td style="text-align: center;">󰃵󰃻󰄍</td>
<td style="text-align: center;"></td>
<td style="text-align: center;">󰃹󰃺󰄍</td>
<td style="text-align: center;">󰃰󰃺󰄍</td>
<td style="text-align: center;">󰃳󰃺󰄍</td>
<td style="text-align: center;"></td>
</tr>
<tr>
<td style="text-align: center;">󰇘类干音</td>
<td style="text-align: center;">󰃼󰃼󰄋</td>
<td style="text-align: center;">󰃰󰃼󰄋</td>
<td style="text-align: center;">󰃳󰃼󰄋</td>
<td style="text-align: center;">󰃶󰃼󰄋</td>
<td style="text-align: center;">󰃾󰃽󰄋</td>
<td style="text-align: center;">󰃲󰃽󰄋</td>
<td style="text-align: center;">󰃵󰃽󰄋</td>
<td style="text-align: center;">󰃸󰃽󰄋</td>
<td style="text-align: center;">󰃾󰃾󰄍</td>
<td style="text-align: center;">󰃲󰃾󰄍</td>
<td style="text-align: center;">󰃵󰃾󰄍</td>
<td style="text-align: center;">󰃸󰃾󰄍</td>
<td style="text-align: center;">󰃼󰃽󰄍</td>
<td style="text-align: center;">󰃰󰃽󰄍</td>
<td style="text-align: center;">󰃳󰃽󰄍</td>
<td style="text-align: center;">󰃶󰃽󰄍</td>
</tr>
</tbody>
</table>

干音分别采用半宽字符、音符序列、用上标来标调的组合式音符、《国际音标》和《汉语拼音方案》五种常用方式记音的对应关系列表见表。

表 7干音的常用的几种记音方式的对应关系

<table style="width:100%;">
<colgroup>
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 3%" />
<col style="width: 4%" />
<col style="width: 4%" />
<col style="width: 4%" />
<col style="width: 4%" />
<col style="width: 4%" />
<col style="width: 4%" />
<col style="width: 4%" />
<col style="width: 4%" />
<col style="width: 6%" />
<col style="width: 6%" />
<col style="width: 7%" />
<col style="width: 6%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
</colgroup>
<thead>
<tr>
<th colspan="4" style="text-align: center;">半宽字符</th>
<th colspan="4" style="text-align: center;">音符序列</th>
<th colspan="4" style="text-align: center;">组合式</th>
<th colspan="4" style="text-align: center;">《国际音标》</th>
<th colspan="4" style="text-align: center;">《汉语拼音方案》</th>
</tr>
<tr>
<th style="text-align: center;">高</th>
<th style="text-align: center;">升</th>
<th style="text-align: center;">低</th>
<th style="text-align: center;">降</th>
<th style="text-align: center;">高</th>
<th style="text-align: center;">升</th>
<th style="text-align: center;">低</th>
<th style="text-align: center;">降</th>
<th style="text-align: center;">高</th>
<th style="text-align: center;">升</th>
<th style="text-align: center;">低</th>
<th style="text-align: center;">降</th>
<th style="text-align: center;">高</th>
<th style="text-align: center;">升</th>
<th style="text-align: center;">低</th>
<th style="text-align: center;">降</th>
<th style="text-align: center;">高</th>
<th style="text-align: center;">升</th>
<th style="text-align: center;">低</th>
<th style="text-align: center;">降</th>
</tr>
</thead>
<tbody>
<tr>
<td style="text-align: center;">󰀠</td>
<td style="text-align: center;">󰀡</td>
<td style="text-align: center;">󰀢</td>
<td style="text-align: center;">󰀣</td>
<td style="text-align: center;">󰃰󰃰󰃰</td>
<td style="text-align: center;">󰃲󰃱󰃰</td>
<td style="text-align: center;">󰃲󰃲󰃲</td>
<td style="text-align: center;">󰃰󰃱󰃲</td>
<td style="text-align: center;">󰌠󰌠󰌠</td>
<td style="text-align: center;">󰌤󰌡󰌠</td>
<td style="text-align: center;">󰌤󰌤󰌤</td>
<td style="text-align: center;">󰌠󰌡󰌤</td>
<td style="text-align: center;">i⁵⁵</td>
<td style="text-align: center;">i³⁵</td>
<td style="text-align: center;">i²¹¹</td>
<td style="text-align: center;">i⁵¹</td>
<td style="text-align: center;">󰌡</td>
<td style="text-align: center;">󰌠</td>
<td style="text-align: center;">ǐ</td>
<td style="text-align: center;">󰌤</td>
</tr>
<tr>
<td style="text-align: center;">󰀤</td>
<td style="text-align: center;">󰀥</td>
<td style="text-align: center;">󰀦</td>
<td style="text-align: center;">󰀧</td>
<td style="text-align: center;">󰃳󰃳󰃳</td>
<td style="text-align: center;">󰃵󰃴󰃳</td>
<td style="text-align: center;">󰃵󰃵󰃵</td>
<td style="text-align: center;">󰃳󰃴󰃵</td>
<td style="text-align: center;">󰌪󰌪󰌪</td>
<td style="text-align: center;">󰌮󰌫󰌪</td>
<td style="text-align: center;">󰌮󰌮󰌮</td>
<td style="text-align: center;">󰌪󰌫󰌮</td>
<td style="text-align: center;">u⁵⁵</td>
<td style="text-align: center;">u³⁵</td>
<td style="text-align: center;">u²¹¹</td>
<td style="text-align: center;">u⁵¹</td>
<td style="text-align: center;">󰉔</td>
<td style="text-align: center;">󰉕</td>
<td style="text-align: center;">󰉖</td>
<td style="text-align: center;">󰉗</td>
</tr>
<tr>
<td style="text-align: center;">󰀨</td>
<td style="text-align: center;">󰀩</td>
<td style="text-align: center;">󰀪</td>
<td style="text-align: center;">󰀫</td>
<td style="text-align: center;">󰃶󰃶󰃶</td>
<td style="text-align: center;">󰃸󰃷󰃶</td>
<td style="text-align: center;">󰃸󰃸󰃸</td>
<td style="text-align: center;">󰃶󰃷󰃸</td>
<td style="text-align: center;">󰌴󰌴󰌴</td>
<td style="text-align: center;">󰌸󰌵󰌴</td>
<td style="text-align: center;">󰌸󰌸󰌸</td>
<td style="text-align: center;">󰌴󰌵󰌸</td>
<td style="text-align: center;">ʏ⁵⁵</td>
<td style="text-align: center;">ʏ³⁵</td>
<td style="text-align: center;">ʏ²¹¹</td>
<td style="text-align: center;">ʏ⁵¹</td>
<td style="text-align: center;">󰉘</td>
<td style="text-align: center;">󰉙</td>
<td style="text-align: center;">󰉚</td>
<td style="text-align: center;">󰉛</td>
</tr>
<tr>
<td rowspan="2" style="text-align: center;">󰁘</td>
<td rowspan="2" style="text-align: center;">󰁙</td>
<td rowspan="2" style="text-align: center;">󰁚</td>
<td rowspan="2" style="text-align: center;">󰁛</td>
<td rowspan="2" style="text-align: center;">󰄂󰄂󰄂</td>
<td rowspan="2" style="text-align: center;">󰄄󰄃󰄂</td>
<td rowspan="2" style="text-align: center;">󰄄󰄄󰄄</td>
<td rowspan="2" style="text-align: center;">󰄂󰄃󰄄</td>
<td rowspan="2" style="text-align: center;">󰍵󰍵󰍵</td>
<td rowspan="2" style="text-align: center;">󰍹󰍶󰍵</td>
<td rowspan="2" style="text-align: center;">󰍹󰍹󰍹</td>
<td rowspan="2" style="text-align: center;">󰍵󰍶󰍹</td>
<td style="text-align: center;">ɿ⁵⁵</td>
<td style="text-align: center;">ɿ³⁵</td>
<td style="text-align: center;">ɿ²¹¹</td>
<td style="text-align: center;">ɿ⁵¹</td>
<td rowspan="2" style="text-align: center;">󰌡</td>
<td rowspan="2" style="text-align: center;">󰌠</td>
<td rowspan="2" style="text-align: center;">ǐ</td>
<td rowspan="2" style="text-align: center;">󰌤</td>
</tr>
<tr>
<td style="text-align: center;">ʅ⁵⁵</td>
<td style="text-align: center;">ʅ³⁵</td>
<td style="text-align: center;">ʅ²¹¹</td>
<td style="text-align: center;">ʅ⁵¹</td>
</tr>
<tr>
<td style="text-align: center;">󰁜</td>
<td style="text-align: center;">󰁝</td>
<td style="text-align: center;">󰁞</td>
<td style="text-align: center;">󰁟</td>
<td style="text-align: center;">󰄅󰄅󰄅</td>
<td style="text-align: center;">󰄇󰄆󰄅</td>
<td style="text-align: center;">󰄇󰄇󰄇</td>
<td style="text-align: center;">󰄅󰄆󰄇</td>
<td style="text-align: center;">󰎄󰎄󰎄</td>
<td style="text-align: center;">󰎈󰎅󰎄</td>
<td style="text-align: center;">󰎈󰎈󰎈</td>
<td style="text-align: center;">󰎄󰎅󰎈</td>
<td style="text-align: center;">ɚ⁵⁵</td>
<td style="text-align: center;">ɚ³⁵</td>
<td style="text-align: center;">ɚ²¹¹</td>
<td style="text-align: center;">ɚ⁵¹</td>
<td style="text-align: center;">󰍧r</td>
<td style="text-align: center;">󰍦r</td>
<td style="text-align: center;">ěr</td>
<td style="text-align: center;">󰍪r</td>
</tr>
<tr>
<td style="text-align: center;">󰁤</td>
<td style="text-align: center;">󰁥</td>
<td style="text-align: center;">󰁦</td>
<td style="text-align: center;">󰁧</td>
<td style="text-align: center;">󰄈󰄈󰄈</td>
<td style="text-align: center;">󰄊󰄉󰄈</td>
<td style="text-align: center;">󰄊󰄊󰄊</td>
<td style="text-align: center;">󰄈󰄉󰄊</td>
<td style="text-align: center;">󰎓󰎓󰎓</td>
<td style="text-align: center;">󰎗󰎔󰎓</td>
<td style="text-align: center;">󰎗󰎗󰎗</td>
<td style="text-align: center;">󰎓󰎔󰎗</td>
<td style="text-align: center;">n⁵⁵</td>
<td style="text-align: center;">n³⁵</td>
<td style="text-align: center;">n²¹¹</td>
<td style="text-align: center;">n⁵¹</td>
<td style="text-align: center;">󰉬</td>
<td style="text-align: center;">󰉭</td>
<td style="text-align: center;">󰉮</td>
<td style="text-align: center;">󰉯</td>
</tr>
<tr>
<td style="text-align: center;">󰁨</td>
<td style="text-align: center;">󰁩</td>
<td style="text-align: center;">󰁪</td>
<td style="text-align: center;">󰁫</td>
<td style="text-align: center;">󰄋󰄋󰄋</td>
<td style="text-align: center;">󰄍󰄌󰄋</td>
<td style="text-align: center;">󰄍󰄍󰄍</td>
<td style="text-align: center;">󰄋󰄌󰄍</td>
<td style="text-align: center;">󰎘󰎘󰎘</td>
<td style="text-align: center;">󰎜󰎙󰎘</td>
<td style="text-align: center;">󰎜󰎜󰎜</td>
<td style="text-align: center;">󰎘󰎙󰎜</td>
<td style="text-align: center;">ŋ⁵⁵</td>
<td style="text-align: center;">ŋ³⁵</td>
<td style="text-align: center;">ŋ²¹¹</td>
<td style="text-align: center;">ŋ⁵¹</td>
<td style="text-align: center;">󰉬ɡ</td>
<td style="text-align: center;">󰉭ɡ</td>
<td style="text-align: center;">󰉮ɡ</td>
<td style="text-align: center;">󰉯ɡ</td>
</tr>
<tr>
<td style="text-align: center;">󰀬</td>
<td style="text-align: center;">󰀭</td>
<td style="text-align: center;">󰀮</td>
<td style="text-align: center;">󰀯</td>
<td style="text-align: center;">󰃹󰃹󰃹</td>
<td style="text-align: center;">󰃻󰃺󰃹</td>
<td style="text-align: center;">󰃻󰃻󰃻</td>
<td style="text-align: center;">󰃹󰃺󰃻</td>
<td style="text-align: center;">󰌾󰌾󰌾</td>
<td style="text-align: center;">󰍂󰌿󰌾</td>
<td style="text-align: center;">󰍂󰍂󰍂</td>
<td style="text-align: center;">󰌾󰌿󰍂</td>
<td style="text-align: center;">ᴀ⁵⁵</td>
<td style="text-align: center;">ᴀ³⁵</td>
<td style="text-align: center;">ᴀ²¹¹</td>
<td style="text-align: center;">ᴀ⁵¹</td>
<td style="text-align: center;">󰉜</td>
<td style="text-align: center;">󰉝</td>
<td style="text-align: center;">󰉞</td>
<td style="text-align: center;">󰉟</td>
</tr>
<tr>
<td rowspan="2" style="text-align: center;">󰀸</td>
<td rowspan="2" style="text-align: center;">󰀹</td>
<td rowspan="2" style="text-align: center;">󰀺</td>
<td rowspan="2" style="text-align: center;">󰀻</td>
<td rowspan="2" style="text-align: center;">󰃼󰃼󰃼</td>
<td rowspan="2" style="text-align: center;">󰃾󰃽󰃼</td>
<td rowspan="2" style="text-align: center;">󰃾󰃾󰃾</td>
<td rowspan="2" style="text-align: center;">󰃼󰃽󰃾</td>
<td rowspan="2" style="text-align: center;">󰍒󰍒󰍒</td>
<td rowspan="2" style="text-align: center;">󰍖󰍓󰍒</td>
<td rowspan="2" style="text-align: center;">󰍖󰍖󰍖</td>
<td rowspan="2" style="text-align: center;">󰍒󰍓󰍖</td>
<td style="text-align: center;">o⁵⁵</td>
<td style="text-align: center;">o³⁵</td>
<td style="text-align: center;">o²¹¹</td>
<td style="text-align: center;">o⁵¹</td>
<td style="text-align: center;">󰉠</td>
<td style="text-align: center;">󰉡</td>
<td style="text-align: center;">󰉢</td>
<td style="text-align: center;">󰉣</td>
</tr>
<tr>
<td style="text-align: center;">ɤ⁵⁵</td>
<td style="text-align: center;">ɤ³⁵</td>
<td style="text-align: center;">ɤ²¹¹</td>
<td style="text-align: center;">ɤ⁵¹</td>
<td style="text-align: center;">󰍧</td>
<td style="text-align: center;">󰍦</td>
<td style="text-align: center;">ě</td>
<td style="text-align: center;">󰍪</td>
</tr>
<tr>
<td style="text-align: center;">󰁈</td>
<td style="text-align: center;">󰁉</td>
<td style="text-align: center;">󰁊</td>
<td style="text-align: center;">󰁋</td>
<td style="text-align: center;">󰃿󰃿󰃿</td>
<td style="text-align: center;">󰄁󰄀󰃿</td>
<td style="text-align: center;">󰄁󰄁󰄁</td>
<td style="text-align: center;">󰃿󰄀󰄁</td>
<td style="text-align: center;">󰍡󰍡󰍡</td>
<td style="text-align: center;">󰍥󰍢󰍡</td>
<td style="text-align: center;">󰍥󰍥󰍥</td>
<td style="text-align: center;">󰍡󰍢󰍥</td>
<td style="text-align: center;">ᴇ⁵⁵</td>
<td style="text-align: center;">ᴇ³⁵</td>
<td style="text-align: center;">ᴇ²¹¹</td>
<td style="text-align: center;">ᴇ⁵¹</td>
<td style="text-align: center;">󰉨</td>
<td style="text-align: center;">ế</td>
<td style="text-align: center;">󰉪</td>
<td style="text-align: center;">ề</td>
</tr>
<tr>
<td style="text-align: center;">󰀰</td>
<td style="text-align: center;">󰀱</td>
<td style="text-align: center;">󰀲</td>
<td style="text-align: center;">󰀳</td>
<td style="text-align: center;">󰃰󰃹󰃹</td>
<td style="text-align: center;">󰃲󰃺󰃹</td>
<td style="text-align: center;">󰃲󰃻󰃻</td>
<td style="text-align: center;">󰃰󰃺󰃻</td>
<td style="text-align: center;">󰌠󰌾󰌾</td>
<td style="text-align: center;">󰌤󰌿󰌾</td>
<td style="text-align: center;">󰌤󰍂󰍂</td>
<td style="text-align: center;">󰌠󰌿󰍂</td>
<td style="text-align: center;">iᴀ⁵⁵</td>
<td style="text-align: center;">iᴀ³⁵</td>
<td style="text-align: center;">iᴀ²¹¹</td>
<td style="text-align: center;">iᴀ⁵¹</td>
<td style="text-align: center;">i󰉜</td>
<td style="text-align: center;">i󰉝</td>
<td style="text-align: center;">i󰉞</td>
<td style="text-align: center;">i󰉟</td>
</tr>
<tr>
<td style="text-align: center;">󰀴</td>
<td style="text-align: center;">󰀵</td>
<td style="text-align: center;">󰀶</td>
<td style="text-align: center;">󰀷</td>
<td style="text-align: center;">󰃳󰃹󰃹</td>
<td style="text-align: center;">󰃵󰃺󰃹</td>
<td style="text-align: center;">󰃵󰃻󰃻</td>
<td style="text-align: center;">󰃳󰃺󰃻</td>
<td style="text-align: center;">󰌪󰌾󰌾</td>
<td style="text-align: center;">󰌮󰌿󰌾</td>
<td style="text-align: center;">󰌮󰍂󰍂</td>
<td style="text-align: center;">󰌪󰌿󰍂</td>
<td style="text-align: center;">uᴀ⁵⁵</td>
<td style="text-align: center;">uᴀ³⁵</td>
<td style="text-align: center;">uᴀ²¹¹</td>
<td style="text-align: center;">uᴀ⁵¹</td>
<td style="text-align: center;">u󰉜</td>
<td style="text-align: center;">u󰉝</td>
<td style="text-align: center;">u󰉞</td>
<td style="text-align: center;">u󰉟</td>
</tr>
<tr>
<td style="text-align: center;">󰁀</td>
<td style="text-align: center;">󰁁</td>
<td style="text-align: center;">󰁂</td>
<td style="text-align: center;">󰁃</td>
<td style="text-align: center;">󰃳󰃼󰃼</td>
<td style="text-align: center;">󰃵󰃽󰃼</td>
<td style="text-align: center;">󰃵󰃾󰃾</td>
<td style="text-align: center;">󰃳󰃽󰃾</td>
<td style="text-align: center;">󰌪󰍒󰍒</td>
<td style="text-align: center;">󰌮󰍓󰍒</td>
<td style="text-align: center;">󰌮󰍖󰍖</td>
<td style="text-align: center;">󰌪󰍓󰍖</td>
<td style="text-align: center;">uo⁵⁵</td>
<td style="text-align: center;">uo³⁵</td>
<td style="text-align: center;">uo²¹¹</td>
<td style="text-align: center;">uo⁵¹</td>
<td style="text-align: center;">u󰉠</td>
<td style="text-align: center;">u󰉡</td>
<td style="text-align: center;">u󰉢</td>
<td style="text-align: center;">u󰉣</td>
</tr>
<tr>
<td style="text-align: center;">󰁌</td>
<td style="text-align: center;">󰁍</td>
<td style="text-align: center;">󰁎</td>
<td style="text-align: center;">󰁏</td>
<td style="text-align: center;">󰃰󰃿󰃿</td>
<td style="text-align: center;">󰃲󰄀󰃿</td>
<td style="text-align: center;">󰃲󰄁󰄁</td>
<td style="text-align: center;">󰃰󰄀󰄁</td>
<td style="text-align: center;">󰌠󰍡󰍡</td>
<td style="text-align: center;">󰌤󰍢󰍡</td>
<td style="text-align: center;">󰌤󰍥󰍥</td>
<td style="text-align: center;">󰌠󰍢󰍥</td>
<td style="text-align: center;">iᴇ⁵⁵</td>
<td style="text-align: center;">iᴇ³⁵</td>
<td style="text-align: center;">iᴇ²¹¹</td>
<td style="text-align: center;">iᴇ⁵¹</td>
<td style="text-align: center;">i󰍧</td>
<td style="text-align: center;">i󰍦</td>
<td style="text-align: center;">iě</td>
<td style="text-align: center;">i󰍪</td>
</tr>
<tr>
<td style="text-align: center;">󰁐</td>
<td style="text-align: center;">󰁑</td>
<td style="text-align: center;">󰁒</td>
<td style="text-align: center;">󰁓</td>
<td style="text-align: center;">󰃶󰃿󰃿</td>
<td style="text-align: center;">󰃸󰄀󰃿</td>
<td style="text-align: center;">󰃸󰄁󰄁</td>
<td style="text-align: center;">󰃶󰄀󰄁</td>
<td style="text-align: center;">󰌴󰍡󰍡</td>
<td style="text-align: center;">󰌸󰍢󰍡</td>
<td style="text-align: center;">󰌸󰍥󰍥</td>
<td style="text-align: center;">󰌴󰍢󰍥</td>
<td style="text-align: center;">ʏᴇ⁵⁵</td>
<td style="text-align: center;">ʏᴇ³⁵</td>
<td style="text-align: center;">ʏᴇ²¹¹</td>
<td style="text-align: center;">ʏᴇ⁵¹</td>
<td style="text-align: center;">ü󰍧</td>
<td style="text-align: center;">ü󰍦</td>
<td style="text-align: center;">üě</td>
<td style="text-align: center;">ü󰍪</td>
</tr>
<tr>
<td style="text-align: center;">󰁬</td>
<td style="text-align: center;">󰁭</td>
<td style="text-align: center;">󰁮</td>
<td style="text-align: center;">󰁯</td>
<td style="text-align: center;">󰃹󰃹󰃰</td>
<td style="text-align: center;">󰃻󰃺󰃰</td>
<td style="text-align: center;">󰃻󰃻󰃲</td>
<td style="text-align: center;">󰃹󰃺󰃲</td>
<td style="text-align: center;">󰌾󰌾󰌠</td>
<td style="text-align: center;">󰍂󰌿󰌠</td>
<td style="text-align: center;">󰍂󰍂󰌤</td>
<td style="text-align: center;">󰌾󰌿󰌤</td>
<td style="text-align: center;">æɪ⁵⁵</td>
<td style="text-align: center;">æɪ³⁵</td>
<td style="text-align: center;">æɪ²¹¹</td>
<td style="text-align: center;">æɪ⁵¹</td>
<td style="text-align: center;">󰉜i</td>
<td style="text-align: center;">󰉝i</td>
<td style="text-align: center;">󰉞i</td>
<td style="text-align: center;">󰉟i</td>
</tr>
<tr>
<td style="text-align: center;">󰁴</td>
<td style="text-align: center;">󰁵</td>
<td style="text-align: center;">󰁶</td>
<td style="text-align: center;">󰁷</td>
<td style="text-align: center;">󰃿󰃿󰃰</td>
<td style="text-align: center;">󰄁󰄀󰃰</td>
<td style="text-align: center;">󰄁󰄁󰃲</td>
<td style="text-align: center;">󰃿󰄀󰃲</td>
<td style="text-align: center;">󰍡󰍡󰌠</td>
<td style="text-align: center;">󰍥󰍢󰌠</td>
<td style="text-align: center;">󰍥󰍥󰌤</td>
<td style="text-align: center;">󰍡󰍢󰌤</td>
<td style="text-align: center;">eɪ⁵⁵</td>
<td style="text-align: center;">eɪ³⁵</td>
<td style="text-align: center;">eɪ²¹¹</td>
<td style="text-align: center;">eɪ⁵¹</td>
<td style="text-align: center;">󰍧i</td>
<td style="text-align: center;">󰍦i</td>
<td style="text-align: center;">ěi</td>
<td style="text-align: center;">󰍪i</td>
</tr>
<tr>
<td style="text-align: center;">󰁼</td>
<td style="text-align: center;">󰁽</td>
<td style="text-align: center;">󰁾</td>
<td style="text-align: center;">󰁿</td>
<td style="text-align: center;">󰃹󰃹󰃳</td>
<td style="text-align: center;">󰃻󰃺󰃳</td>
<td style="text-align: center;">󰃻󰃻󰃵</td>
<td style="text-align: center;">󰃹󰃺󰃵</td>
<td style="text-align: center;">󰌾󰌾󰌪</td>
<td style="text-align: center;">󰍂󰌿󰌪</td>
<td style="text-align: center;">󰍂󰍂󰌮</td>
<td style="text-align: center;">󰌾󰌿󰌮</td>
<td style="text-align: center;">ɑᴜ⁵⁵</td>
<td style="text-align: center;">ɑᴜ³⁵</td>
<td style="text-align: center;">ɑᴜ²¹¹</td>
<td style="text-align: center;">ɑᴜ⁵¹</td>
<td style="text-align: center;">󰉜o</td>
<td style="text-align: center;">󰉝o</td>
<td style="text-align: center;">󰉞o</td>
<td style="text-align: center;">󰉟o</td>
</tr>
<tr>
<td style="text-align: center;">󰂄</td>
<td style="text-align: center;">󰂅</td>
<td style="text-align: center;">󰂆</td>
<td style="text-align: center;">󰂇</td>
<td style="text-align: center;">󰃼󰃼󰃳</td>
<td style="text-align: center;">󰃾󰃽󰃳</td>
<td style="text-align: center;">󰃾󰃾󰃵</td>
<td style="text-align: center;">󰃼󰃽󰃵</td>
<td style="text-align: center;">󰍒󰍒󰌪</td>
<td style="text-align: center;">󰍖󰍓󰌪</td>
<td style="text-align: center;">󰍖󰍖󰌮</td>
<td style="text-align: center;">󰍒󰍓󰌮</td>
<td style="text-align: center;">ɤᴜ⁵⁵</td>
<td style="text-align: center;">ɤᴜ³⁵</td>
<td style="text-align: center;">ɤᴜ²¹¹</td>
<td style="text-align: center;">ɤᴜ⁵¹</td>
<td style="text-align: center;">󰉠u</td>
<td style="text-align: center;">󰉡u</td>
<td style="text-align: center;">󰉢u</td>
<td style="text-align: center;">󰉣u</td>
</tr>
<tr>
<td style="text-align: center;">󰂌</td>
<td style="text-align: center;">󰂍</td>
<td style="text-align: center;">󰂎</td>
<td style="text-align: center;">󰂏</td>
<td style="text-align: center;">󰃹󰃹󰄈</td>
<td style="text-align: center;">󰃻󰃺󰄈</td>
<td style="text-align: center;">󰃻󰃻󰄊</td>
<td style="text-align: center;">󰃹󰃺󰄊</td>
<td style="text-align: center;">󰌾󰌾󰎓</td>
<td style="text-align: center;">󰍂󰌿󰎓</td>
<td style="text-align: center;">󰍂󰍂󰎗</td>
<td style="text-align: center;">󰌾󰌿󰎗</td>
<td style="text-align: center;">an⁵⁵</td>
<td style="text-align: center;">an³⁵</td>
<td style="text-align: center;">an²¹¹</td>
<td style="text-align: center;">an⁵¹</td>
<td style="text-align: center;">󰉜n</td>
<td style="text-align: center;">󰉝n</td>
<td style="text-align: center;">󰉞n</td>
<td style="text-align: center;">󰉟n</td>
</tr>
<tr>
<td style="text-align: center;">󰂜</td>
<td style="text-align: center;">󰂝</td>
<td style="text-align: center;">󰂞</td>
<td style="text-align: center;">󰂟</td>
<td style="text-align: center;">󰃿󰃿󰄈</td>
<td style="text-align: center;">󰄁󰄀󰄈</td>
<td style="text-align: center;">󰄁󰄁󰄊</td>
<td style="text-align: center;">󰃿󰄀󰄊</td>
<td style="text-align: center;">󰍡󰍡󰎓</td>
<td style="text-align: center;">󰍥󰍢󰎓</td>
<td style="text-align: center;">󰍥󰍥󰎗</td>
<td style="text-align: center;">󰍡󰍢󰎗</td>
<td style="text-align: center;">ən⁵⁵</td>
<td style="text-align: center;">ən³⁵</td>
<td style="text-align: center;">ən²¹¹</td>
<td style="text-align: center;">ən⁵¹</td>
<td style="text-align: center;">󰍧n</td>
<td style="text-align: center;">󰍦n</td>
<td style="text-align: center;">ěn</td>
<td style="text-align: center;">󰍪n</td>
</tr>
<tr>
<td style="text-align: center;">󰂬</td>
<td style="text-align: center;">󰂭</td>
<td style="text-align: center;">󰂮</td>
<td style="text-align: center;">󰂯</td>
<td style="text-align: center;">󰃹󰃹󰄋</td>
<td style="text-align: center;">󰃻󰃺󰄋</td>
<td style="text-align: center;">󰃻󰃻󰄍</td>
<td style="text-align: center;">󰃹󰃺󰄍</td>
<td style="text-align: center;">󰌾󰌾󰎘</td>
<td style="text-align: center;">󰍂󰌿󰎘</td>
<td style="text-align: center;">󰍂󰍂󰎜</td>
<td style="text-align: center;">󰌾󰌿󰎜</td>
<td style="text-align: center;">ɑŋ⁵⁵</td>
<td style="text-align: center;">ɑŋ³⁵</td>
<td style="text-align: center;">ɑŋ²¹¹</td>
<td style="text-align: center;">ɑŋ⁵¹</td>
<td style="text-align: center;">󰉜nɡ</td>
<td style="text-align: center;">󰉝nɡ</td>
<td style="text-align: center;">󰉞nɡ</td>
<td style="text-align: center;">󰉟nɡ</td>
</tr>
<tr>
<td style="text-align: center;">󰂸</td>
<td style="text-align: center;">󰂹</td>
<td style="text-align: center;">󰂺</td>
<td style="text-align: center;">󰂻</td>
<td style="text-align: center;">󰃼󰃼󰄋</td>
<td style="text-align: center;">󰃾󰃽󰄋</td>
<td style="text-align: center;">󰃾󰃾󰄍</td>
<td style="text-align: center;">󰃼󰃽󰄍</td>
<td style="text-align: center;">󰍒󰍒󰎘</td>
<td style="text-align: center;">󰍖󰍓󰎘</td>
<td style="text-align: center;">󰍖󰍖󰎜</td>
<td style="text-align: center;">󰍒󰍓󰎜</td>
<td style="text-align: center;">ɤŋ⁵⁵</td>
<td style="text-align: center;">ɤŋ³⁵</td>
<td style="text-align: center;">ɤŋ²¹¹</td>
<td style="text-align: center;">ɤŋ⁵¹</td>
<td style="text-align: center;">󰍧nɡ</td>
<td style="text-align: center;">󰍦nɡ</td>
<td style="text-align: center;">ěnɡ</td>
<td style="text-align: center;">󰍪nɡ</td>
</tr>
<tr>
<td style="text-align: center;">󰁰</td>
<td style="text-align: center;">󰁱</td>
<td style="text-align: center;">󰁲</td>
<td style="text-align: center;">󰁳</td>
<td style="text-align: center;">󰃳󰃹󰃰</td>
<td style="text-align: center;">󰃵󰃺󰃰</td>
<td style="text-align: center;">󰃵󰃻󰃲</td>
<td style="text-align: center;">󰃳󰃺󰃲</td>
<td style="text-align: center;">󰌪󰌾󰌠</td>
<td style="text-align: center;">󰌮󰌿󰌠</td>
<td style="text-align: center;">󰌮󰍂󰌤</td>
<td style="text-align: center;">󰌪󰌿󰌤</td>
<td style="text-align: center;">uæɪ⁵⁵</td>
<td style="text-align: center;">uæɪ³⁵</td>
<td style="text-align: center;">uæɪ²¹¹</td>
<td style="text-align: center;">uæɪ⁵¹</td>
<td style="text-align: center;">u󰉜i</td>
<td style="text-align: center;">u󰉝i</td>
<td style="text-align: center;">u󰉞i</td>
<td style="text-align: center;">u󰉟i</td>
</tr>
<tr>
<td style="text-align: center;">󰁸</td>
<td style="text-align: center;">󰁹</td>
<td style="text-align: center;">󰁺</td>
<td style="text-align: center;">󰁻</td>
<td style="text-align: center;">󰃳󰃿󰃰</td>
<td style="text-align: center;">󰃵󰄀󰃰</td>
<td style="text-align: center;">󰃵󰄁󰃲</td>
<td style="text-align: center;">󰃳󰄀󰃲</td>
<td style="text-align: center;">󰌪󰍡󰌠</td>
<td style="text-align: center;">󰌮󰍢󰌠</td>
<td style="text-align: center;">󰌮󰍥󰌤</td>
<td style="text-align: center;">󰌪󰍢󰌤</td>
<td style="text-align: center;">ueɪ⁵⁵</td>
<td style="text-align: center;">ueɪ³⁵</td>
<td style="text-align: center;">ueɪ²¹¹</td>
<td style="text-align: center;">ueɪ⁵¹</td>
<td style="text-align: center;">u󰍧i</td>
<td style="text-align: center;">u󰍦i</td>
<td style="text-align: center;">uěi</td>
<td style="text-align: center;">u󰍪i</td>
</tr>
<tr>
<td style="text-align: center;">󰂀</td>
<td style="text-align: center;">󰂁</td>
<td style="text-align: center;">󰂂</td>
<td style="text-align: center;">󰂃</td>
<td style="text-align: center;">󰃰󰃹󰃳</td>
<td style="text-align: center;">󰃲󰃺󰃳</td>
<td style="text-align: center;">󰃲󰃻󰃵</td>
<td style="text-align: center;">󰃰󰃺󰃵</td>
<td style="text-align: center;">󰌠󰌾󰌪</td>
<td style="text-align: center;">󰌤󰌿󰌪</td>
<td style="text-align: center;">󰌤󰍂󰌮</td>
<td style="text-align: center;">󰌠󰌿󰌮</td>
<td style="text-align: center;">iɑᴜ⁵⁵</td>
<td style="text-align: center;">iɑᴜ³⁵</td>
<td style="text-align: center;">iɑᴜ²¹¹</td>
<td style="text-align: center;">iɑᴜ⁵¹</td>
<td style="text-align: center;">i󰉜o</td>
<td style="text-align: center;">i󰉝o</td>
<td style="text-align: center;">i󰉞o</td>
<td style="text-align: center;">i󰉟o</td>
</tr>
<tr>
<td style="text-align: center;">󰂈</td>
<td style="text-align: center;">󰂉</td>
<td style="text-align: center;">󰂊</td>
<td style="text-align: center;">󰂋</td>
<td style="text-align: center;">󰃰󰃼󰃳</td>
<td style="text-align: center;">󰃲󰃽󰃳</td>
<td style="text-align: center;">󰃲󰃾󰃵</td>
<td style="text-align: center;">󰃰󰃽󰃵</td>
<td style="text-align: center;">󰌠󰍒󰌪</td>
<td style="text-align: center;">󰌤󰍘󰌮</td>
<td style="text-align: center;">󰌤󰍖󰌮</td>
<td style="text-align: center;">󰌠󰍓󰌮</td>
<td style="text-align: center;">iɤᴜ⁵⁵</td>
<td style="text-align: center;">iɤᴜ³⁵</td>
<td style="text-align: center;">iɤᴜ²¹¹</td>
<td style="text-align: center;">iɤᴜ⁵¹</td>
<td style="text-align: center;">i󰉠u</td>
<td style="text-align: center;">i󰉡u</td>
<td style="text-align: center;">i󰉢u</td>
<td style="text-align: center;">i󰉣u</td>
</tr>
<tr>
<td style="text-align: center;">󰂐</td>
<td style="text-align: center;">󰂑</td>
<td style="text-align: center;">󰂒</td>
<td style="text-align: center;">󰂓</td>
<td style="text-align: center;">󰃰󰃹󰄈</td>
<td style="text-align: center;">󰃲󰃺󰄈</td>
<td style="text-align: center;">󰃲󰃻󰄊</td>
<td style="text-align: center;">󰃰󰃺󰄊</td>
<td style="text-align: center;">󰌠󰌾󰎓</td>
<td style="text-align: center;">󰌤󰌿󰎓</td>
<td style="text-align: center;">󰌤󰍂󰎗</td>
<td style="text-align: center;">󰌠󰌿󰎗</td>
<td style="text-align: center;">iæn⁵⁵</td>
<td style="text-align: center;">iæn³⁵</td>
<td style="text-align: center;">iæn²¹¹</td>
<td style="text-align: center;">iæn⁵¹</td>
<td style="text-align: center;">i󰉜n</td>
<td style="text-align: center;">i󰉝n</td>
<td style="text-align: center;">i󰉞n</td>
<td style="text-align: center;">i󰉟n</td>
</tr>
<tr>
<td style="text-align: center;">󰂔</td>
<td style="text-align: center;">󰂕</td>
<td style="text-align: center;">󰂖</td>
<td style="text-align: center;">󰂗</td>
<td style="text-align: center;">󰃳󰃹󰄈</td>
<td style="text-align: center;">󰃵󰃺󰄈</td>
<td style="text-align: center;">󰃵󰃻󰄊</td>
<td style="text-align: center;">󰃳󰃺󰄊</td>
<td style="text-align: center;">󰌪󰌾󰎓</td>
<td style="text-align: center;">󰌮󰌿󰎓</td>
<td style="text-align: center;">󰌮󰍂󰎗</td>
<td style="text-align: center;">󰌪󰌿󰎗</td>
<td style="text-align: center;">uan⁵⁵</td>
<td style="text-align: center;">uan³⁵</td>
<td style="text-align: center;">uan²¹¹</td>
<td style="text-align: center;">uan⁵¹</td>
<td style="text-align: center;">u󰉜n</td>
<td style="text-align: center;">u󰉝n</td>
<td style="text-align: center;">u󰉞n</td>
<td style="text-align: center;">u󰉟n</td>
</tr>
<tr>
<td style="text-align: center;">󰂘</td>
<td style="text-align: center;">󰂙</td>
<td style="text-align: center;">󰂚</td>
<td style="text-align: center;">󰂛</td>
<td style="text-align: center;">󰃶󰃹󰄈</td>
<td style="text-align: center;">󰃸󰃺󰄈</td>
<td style="text-align: center;">󰃸󰃻󰄊</td>
<td style="text-align: center;">󰃶󰃺󰄊</td>
<td style="text-align: center;">󰌴󰌾󰎓</td>
<td style="text-align: center;">󰌸󰌿󰎓</td>
<td style="text-align: center;">󰌸󰍂󰎗</td>
<td style="text-align: center;">󰌴󰌿󰎗</td>
<td style="text-align: center;">ʏæn⁵⁵</td>
<td style="text-align: center;">ʏæn³⁵</td>
<td style="text-align: center;">ʏæn²¹¹</td>
<td style="text-align: center;">ʏæn⁵¹</td>
<td style="text-align: center;">ü󰉜n</td>
<td style="text-align: center;">ü󰉝n</td>
<td style="text-align: center;">ü󰉞n</td>
<td style="text-align: center;">ü󰉟n</td>
</tr>
<tr>
<td style="text-align: center;">󰂠</td>
<td style="text-align: center;">󰂡</td>
<td style="text-align: center;">󰂢</td>
<td style="text-align: center;">󰂣</td>
<td style="text-align: center;">󰃰󰃿󰄈</td>
<td style="text-align: center;">󰃲󰄀󰄈</td>
<td style="text-align: center;">󰃲󰄁󰄊</td>
<td style="text-align: center;">󰃰󰄀󰄊</td>
<td style="text-align: center;">󰌠󰍡󰎓</td>
<td style="text-align: center;">󰌤󰍢󰎓</td>
<td style="text-align: center;">󰌤󰍥󰎗</td>
<td style="text-align: center;">󰌠󰍢󰎗</td>
<td style="text-align: center;">i󰉸n⁵⁵</td>
<td style="text-align: center;">i󰉸n³⁵</td>
<td style="text-align: center;">i󰉸n²¹¹</td>
<td style="text-align: center;">i󰉸n⁵¹</td>
<td style="text-align: center;">󰌡n</td>
<td style="text-align: center;">󰌠n</td>
<td style="text-align: center;">ǐn</td>
<td style="text-align: center;">󰌤n</td>
</tr>
<tr>
<td style="text-align: center;">󰂤</td>
<td style="text-align: center;">󰂥</td>
<td style="text-align: center;">󰂦</td>
<td style="text-align: center;">󰂧</td>
<td style="text-align: center;">󰃳󰃿󰄈</td>
<td style="text-align: center;">󰃵󰄀󰄈</td>
<td style="text-align: center;">󰃵󰄁󰄊</td>
<td style="text-align: center;">󰃳󰄀󰄊</td>
<td style="text-align: center;">󰌪󰍡󰎓</td>
<td style="text-align: center;">󰌮󰍢󰎓</td>
<td style="text-align: center;">󰌮󰍥󰎗</td>
<td style="text-align: center;">󰌪󰍢󰎗</td>
<td style="text-align: center;">uən⁵⁵</td>
<td style="text-align: center;">uən³⁵</td>
<td style="text-align: center;">uən²¹¹</td>
<td style="text-align: center;">uən⁵¹</td>
<td style="text-align: center;">u󰍧n</td>
<td style="text-align: center;">u󰍦n</td>
<td style="text-align: center;">uěn</td>
<td style="text-align: center;">u󰍪n</td>
</tr>
<tr>
<td style="text-align: center;">󰂨</td>
<td style="text-align: center;">󰂩</td>
<td style="text-align: center;">󰂪</td>
<td style="text-align: center;">󰂫</td>
<td style="text-align: center;">󰃶󰃿󰄈</td>
<td style="text-align: center;">󰃸󰄀󰄈</td>
<td style="text-align: center;">󰃸󰄁󰄊</td>
<td style="text-align: center;">󰃶󰄀󰄊</td>
<td style="text-align: center;">󰌴󰍡󰎓</td>
<td style="text-align: center;">󰌸󰍢󰎓</td>
<td style="text-align: center;">󰌸󰍥󰎗</td>
<td style="text-align: center;">󰌴󰍢󰎗</td>
<td style="text-align: center;">ʏ󰉸n⁵⁵</td>
<td style="text-align: center;">ʏ󰉸n³⁵</td>
<td style="text-align: center;">ʏ󰉸n²¹¹</td>
<td style="text-align: center;">ʏ󰉸n⁵¹</td>
<td style="text-align: center;">󰉘n</td>
<td style="text-align: center;">󰉙n</td>
<td style="text-align: center;">󰉚n</td>
<td style="text-align: center;">󰉛n</td>
</tr>
<tr>
<td style="text-align: center;">󰂰</td>
<td style="text-align: center;">󰂱</td>
<td style="text-align: center;">󰂲</td>
<td style="text-align: center;">󰂳</td>
<td style="text-align: center;">󰃰󰃹󰄋</td>
<td style="text-align: center;">󰃲󰃺󰄋</td>
<td style="text-align: center;">󰃲󰃻󰄍</td>
<td style="text-align: center;">󰃰󰃺󰄍</td>
<td style="text-align: center;">󰌠󰌾󰎘</td>
<td style="text-align: center;">󰌤󰌿󰎘</td>
<td style="text-align: center;">󰌤󰍂󰎜</td>
<td style="text-align: center;">󰌠󰌿󰎜</td>
<td style="text-align: center;">iɑŋ⁵⁵</td>
<td style="text-align: center;">iɑŋ³⁵</td>
<td style="text-align: center;">iɑŋ²¹¹</td>
<td style="text-align: center;">iɑŋ⁵¹</td>
<td style="text-align: center;">i󰉜nɡ</td>
<td style="text-align: center;">i󰉝nɡ</td>
<td style="text-align: center;">i󰉞nɡ</td>
<td style="text-align: center;">i󰉟nɡ</td>
</tr>
<tr>
<td style="text-align: center;">󰂴</td>
<td style="text-align: center;">󰂵</td>
<td style="text-align: center;">󰂶</td>
<td style="text-align: center;">󰂷</td>
<td style="text-align: center;">󰃳󰃹󰄋</td>
<td style="text-align: center;">󰃵󰃺󰄋</td>
<td style="text-align: center;">󰃵󰃻󰄍</td>
<td style="text-align: center;">󰃳󰃺󰄍</td>
<td style="text-align: center;">󰌪󰌾󰎘</td>
<td style="text-align: center;">󰌮󰌿󰎘</td>
<td style="text-align: center;">󰌮󰍂󰎜</td>
<td style="text-align: center;">󰌪󰌿󰎜</td>
<td style="text-align: center;">uɑŋ⁵⁵</td>
<td style="text-align: center;">uɑŋ³⁵</td>
<td style="text-align: center;">uɑŋ²¹¹</td>
<td style="text-align: center;">uɑŋ⁵¹</td>
<td style="text-align: center;">u󰉜nɡ</td>
<td style="text-align: center;">u󰉝nɡ</td>
<td style="text-align: center;">u󰉞nɡ</td>
<td style="text-align: center;">u󰉟nɡ</td>
</tr>
<tr>
<td style="text-align: center;">󰂼</td>
<td style="text-align: center;">󰂽</td>
<td style="text-align: center;">󰂾</td>
<td style="text-align: center;">󰂿</td>
<td style="text-align: center;">󰃰󰃼󰄋</td>
<td style="text-align: center;">󰃲󰃽󰄋</td>
<td style="text-align: center;">󰃲󰃾󰄍</td>
<td style="text-align: center;">󰃰󰃽󰄍</td>
<td style="text-align: center;">󰌠󰍒󰎘</td>
<td style="text-align: center;">󰌤󰍓󰎘</td>
<td style="text-align: center;">󰌤󰍖󰎜</td>
<td style="text-align: center;">󰌠󰍓󰎜</td>
<td style="text-align: center;">i󰉹ŋ⁵⁵</td>
<td style="text-align: center;">i󰉹ŋ³⁵</td>
<td style="text-align: center;">i󰉹ŋ²¹¹</td>
<td style="text-align: center;">i󰉹ŋ⁵¹</td>
<td style="text-align: center;">󰌡nɡ</td>
<td style="text-align: center;">󰌠nɡ</td>
<td style="text-align: center;">ǐnɡ</td>
<td style="text-align: center;">󰌤nɡ</td>
</tr>
<tr>
<td rowspan="2" style="text-align: center;">󰃀</td>
<td rowspan="2" style="text-align: center;">󰃁</td>
<td rowspan="2" style="text-align: center;">󰃂</td>
<td rowspan="2" style="text-align: center;">󰃃</td>
<td rowspan="2" style="text-align: center;">󰃳󰃼󰄋</td>
<td rowspan="2" style="text-align: center;">󰃵󰃽󰄋</td>
<td rowspan="2" style="text-align: center;">󰃵󰃾󰄍</td>
<td rowspan="2" style="text-align: center;">󰃳󰃽󰄍</td>
<td rowspan="2" style="text-align: center;">󰌪󰍒󰎘</td>
<td rowspan="2" style="text-align: center;">󰌮󰍓󰎘</td>
<td rowspan="2" style="text-align: center;">󰌮󰍖󰎜</td>
<td rowspan="2" style="text-align: center;">󰌪󰍓󰎜</td>
<td style="text-align: center;">uɤŋ⁵⁵</td>
<td style="text-align: center;">uɤŋ³⁵</td>
<td style="text-align: center;">uɤŋ²¹¹</td>
<td style="text-align: center;">uɤŋ⁵¹</td>
<td style="text-align: center;">u󰍧nɡ</td>
<td style="text-align: center;">u󰍦nɡ</td>
<td style="text-align: center;">uěnɡ</td>
<td style="text-align: center;">u󰍪nɡ</td>
</tr>
<tr>
<td style="text-align: center;">u󰉹ŋ⁵⁵</td>
<td style="text-align: center;">u󰉹ŋ³⁵</td>
<td style="text-align: center;">u󰉹ŋ²¹¹</td>
<td style="text-align: center;">u󰉹ŋ⁵¹</td>
<td style="text-align: center;">󰉠nɡ</td>
<td style="text-align: center;">󰉡nɡ</td>
<td style="text-align: center;">󰉢nɡ</td>
<td style="text-align: center;">󰉣nɡ</td>
</tr>
<tr>
<td style="text-align: center;">󰃄</td>
<td style="text-align: center;">󰃅</td>
<td style="text-align: center;">󰃆</td>
<td style="text-align: center;">󰃇</td>
<td style="text-align: center;">󰃶󰃼󰄋</td>
<td style="text-align: center;">󰃸󰃽󰄋</td>
<td style="text-align: center;">󰃸󰃾󰄍</td>
<td style="text-align: center;">󰃶󰃽󰄍</td>
<td style="text-align: center;">󰌴󰍒󰎘</td>
<td style="text-align: center;">󰌸󰍓󰎘</td>
<td style="text-align: center;">󰌸󰍖󰎜</td>
<td style="text-align: center;">󰌴󰍓󰎜</td>
<td style="text-align: center;">y󰉹ŋ⁵⁵</td>
<td style="text-align: center;">y󰉹ŋ³⁵</td>
<td style="text-align: center;">y󰉹ŋ²¹¹</td>
<td style="text-align: center;">y󰉹ŋ⁵¹</td>
<td style="text-align: center;">i󰉠nɡ</td>
<td style="text-align: center;">i󰉡nɡ</td>
<td style="text-align: center;">i󰉢nɡ</td>
<td style="text-align: center;">i󰉣nɡ</td>
</tr>
</tbody>
</table>

在本表中，列标题“高”、“升”、“低”和“降”依序是高调节调、升调节调、低调节调和降调节调的简称。高调节调、升调节调、低调节调和降调节调依序就是高调阴平、升调阳平、低调上声和降调去声。

## 音节

首音和干音的组合与《汉语拼音方案》的带声调的音节一一对应。音元输入法通过输入音元输入音节的首音和干音进而输入每个带声调的音节从而输入与每个音节对应的汉字从而输入词语或语句。

音节表示例：

<table>
<caption><p>表 8首音与󰇘类干音构成的音节</p></caption>
<colgroup>
<col style="width: 15%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
<col style="width: 5%" />
</colgroup>
<thead>
<tr>
<th style="text-align: center;">节调类型</th>
<th colspan="4" style="text-align: center;">高调阴平</th>
<th colspan="4" style="text-align: center;">升调阳平</th>
<th colspan="4" style="text-align: center;">低调上声</th>
<th colspan="4" style="text-align: center;">降调去声</th>
</tr>
<tr>
<th style="text-align: center;">二音类型</th>
<th style="text-align: center;">未</th>
<th style="text-align: center;">噫</th>
<th style="text-align: center;">呜</th>
<th style="text-align: center;">吁</th>
<th style="text-align: center;">未</th>
<th style="text-align: center;">噫</th>
<th style="text-align: center;">呜</th>
<th style="text-align: center;">吁</th>
<th style="text-align: center;">未</th>
<th style="text-align: center;">噫</th>
<th style="text-align: center;">呜</th>
<th style="text-align: center;">吁</th>
<th style="text-align: center;">未</th>
<th style="text-align: center;">噫</th>
<th style="text-align: center;">呜</th>
<th style="text-align: center;">吁</th>
</tr>
<tr>
<th style="text-align: right;"><p>干音</p>
<p>首音</p></th>
<th style="text-align: center;">󰂸</th>
<th style="text-align: center;">󰂼</th>
<th style="text-align: center;">󰃀</th>
<th style="text-align: center;">󰃄</th>
<th style="text-align: center;">󰂹</th>
<th style="text-align: center;">󰂽</th>
<th style="text-align: center;">󰃁</th>
<th style="text-align: center;">󰃅</th>
<th style="text-align: center;">󰂺</th>
<th style="text-align: center;">󰂾</th>
<th style="text-align: center;">󰃂</th>
<th style="text-align: center;">󰃆</th>
<th style="text-align: center;">󰂻</th>
<th style="text-align: center;">󰂿</th>
<th style="text-align: center;">󰃃</th>
<th style="text-align: center;">󰃇</th>
</tr>
<tr>
<th style="text-align: center;">󰀛</th>
<th style="text-align: center;">󰀖󰂸</th>
<th style="text-align: center;">󰀍󰂼</th>
<th style="text-align: center;">󰀄󰃀</th>
<th style="text-align: center;">󰀑󰃄</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀍󰂽</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀑󰃅</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀍󰂾</th>
<th style="text-align: center;">󰀄󰃂</th>
<th style="text-align: center;">󰀑󰃆</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀍󰂿</th>
<th style="text-align: center;">󰀄󰃃</th>
<th style="text-align: center;">󰀑󰃇</th>
</tr>
<tr>
<th style="text-align: center;">󰀀</th>
<th style="text-align: center;">󰀀󰂸</th>
<th style="text-align: center;">󰀀󰂼</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀀󰂹</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀀󰂺</th>
<th style="text-align: center;">󰀀󰂾</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀀󰂻</th>
<th style="text-align: center;">󰀀󰂿</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
</tr>
<tr>
<th style="text-align: center;">󰀁</th>
<th style="text-align: center;">󰀁󰂸</th>
<th style="text-align: center;">󰀁󰂼</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀁󰂹</th>
<th style="text-align: center;">󰀁󰂽</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀁󰂺</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀁󰂻</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
</tr>
<tr>
<th style="text-align: center;">󰀂</th>
<th style="text-align: center;">󰀂󰂸</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀂󰂹</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀂󰂺</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀂󰂻</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
</tr>
<tr>
<th style="text-align: center;">󰀃</th>
<th style="text-align: center;">󰀃󰂸</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀃󰂹</th>
<th style="text-align: center;">󰀃󰂽</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀃󰂺</th>
<th style="text-align: center;">󰀃󰂾</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀃󰂻</th>
<th style="text-align: center;">󰀃󰂿</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
</tr>
<tr>
<th style="text-align: center;">󰀉</th>
<th style="text-align: center;">󰀉󰂸</th>
<th style="text-align: center;">󰀉󰂼</th>
<th style="text-align: center;">󰀉󰃀</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀉󰂺</th>
<th style="text-align: center;">󰀉󰂾</th>
<th style="text-align: center;">󰀉󰃂</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀉󰂻</th>
<th style="text-align: center;">󰀉󰂿</th>
<th style="text-align: center;">󰀉󰃃</th>
<th style="text-align: center;"></th>
</tr>
<tr>
<th style="text-align: center;">󰀊</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀊󰂼</th>
<th style="text-align: center;">󰀊󰃀</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀊󰂹</th>
<th style="text-align: center;">󰀊󰂽</th>
<th style="text-align: center;">󰀊󰃁</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀊󰂾</th>
<th style="text-align: center;">󰀊󰃂</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀊󰂿</th>
<th style="text-align: center;">󰀊󰃃</th>
<th style="text-align: center;"></th>
</tr>
<tr>
<th style="text-align: center;">󰀋</th>
<th style="text-align: center;">󰀋󰂸</th>
<th style="text-align: center;">󰀋󰂼</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀋󰂹</th>
<th style="text-align: center;">󰀋󰂽</th>
<th style="text-align: center;">󰀋󰃁</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀋󰂺</th>
<th style="text-align: center;">󰀋󰂾</th>
<th style="text-align: center;">󰀋󰃂</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀋󰂻</th>
<th style="text-align: center;">󰀋󰂿</th>
<th style="text-align: center;">󰀋󰃃</th>
<th style="text-align: center;"></th>
</tr>
<tr>
<th style="text-align: center;">󰀌</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀌󰂹</th>
<th style="text-align: center;">󰀌󰂽</th>
<th style="text-align: center;">󰀌󰃁</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀌󰂾</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀌󰂿</th>
<th style="text-align: center;">󰀌󰃃</th>
<th style="text-align: center;"></th>
</tr>
<tr>
<th style="text-align: center;">󰀒</th>
<th style="text-align: center;">󰀒󰂸</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀒󰃀</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀒󰂺</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀒󰃂</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀒󰂻</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀒󰃃</th>
<th style="text-align: center;"></th>
</tr>
<tr>
<th style="text-align: center;">󰀓</th>
<th style="text-align: center;">󰀓󰂸</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀓󰃀</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀓󰃂</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀓󰃃</th>
<th style="text-align: center;"></th>
</tr>
<tr>
<th style="text-align: center;">󰀔</th>
<th style="text-align: center;">󰀔󰂸</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀔󰃀</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀔󰂹</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀔󰃁</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀔󰃂</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀔󰂻</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀔󰃃</th>
<th style="text-align: center;"></th>
</tr>
<tr>
<th style="text-align: center;">󰀎</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀎󰂼</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀎󰃄</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀎󰂾</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀎󰃆</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀎󰂿</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
</tr>
<tr>
<th style="text-align: center;">󰀏</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀏󰂼</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀏󰃄</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀏󰂽</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀏󰃅</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀏󰂾</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀏󰂿</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
</tr>
<tr>
<th style="text-align: center;">󰀐</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀐󰂼</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀐󰃄</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀐󰂽</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀐󰃅</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀐󰂾</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀐󰂿</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀐󰃇</th>
</tr>
<tr>
<th style="text-align: center;">󰀗</th>
<th style="text-align: center;">󰀗󰂸</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀗󰃀</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀗󰂺</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀗󰃂</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀗󰂻</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀗󰃃</th>
<th style="text-align: center;"></th>
</tr>
<tr>
<th style="text-align: center;">󰀘</th>
<th style="text-align: center;">󰀘󰂸</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀘󰃀</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀘󰂹</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀘󰃁</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀘󰂺</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀘󰃂</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀘󰂻</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀘󰃃</th>
<th style="text-align: center;"></th>
</tr>
<tr>
<th style="text-align: center;">󰀙</th>
<th style="text-align: center;">󰀙󰂸</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀙󰂹</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀙󰂺</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀙󰂻</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
</tr>
<tr>
<th style="text-align: center;">󰀚</th>
<th style="text-align: center;">󰀚󰂸</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀚󰂹</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀚󰃁</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀚󰃂</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
</tr>
<tr>
<th style="text-align: center;">󰀅</th>
<th style="text-align: center;">󰀅󰂸</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀅󰃀</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀅󰃂</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀅󰂻</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀅󰃃</th>
<th style="text-align: center;"></th>
</tr>
<tr>
<th style="text-align: center;">󰀆</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀆󰃀</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀆󰂹</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀆󰃁</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀆󰂻</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
</tr>
<tr>
<th style="text-align: center;">󰀇</th>
<th style="text-align: center;">󰀇󰂸</th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀇󰃀</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀇󰃂</th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;"></th>
<th style="text-align: center;">󰀇󰃃</th>
<th style="text-align: center;"></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

音节总表见另文。

综述说明，音元输入法是通过输入表示音元的字符输入每个带声调的音节的首音和干音进而输入每个带声调的音节从而输入与每个带声调的音节对应的汉字和语句的音码输入法。首音对应《汉语拼音方案》的声母。干音对应《汉语拼音方案》的带调韵母。强调说明，音元、字符与键位的对应关系可根据设计和使用需要修改。

## 码表

1.  
2.  
3.  

<!-- -->

3.  
4.  

### 单字码表

根据音元系统的音节和《汉语拼音方案》的带声调的音节的一一对应关系构建音元输入法的单字码表。单字码表根据现有带调全拼单字码表转换。

### 词语码表

根据单字码表构建词语码表。词语码表根据现有带调全拼词语码表转换。在输入单字和词语基础上通过字频调整、词频调整和语句及语段生成算法（语义算法）输入语句和语段。

## 结论

音元输入法是平均码长最短的全拼输入法。

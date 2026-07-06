//go:build windows

package yime

func (ime *IME) ensureReverseLookupToolScript() (string, error) {
	return ime.ensureStandaloneToolScript("pime_yime_reverse_lookup_tool.ps1", reverseLookupToolScript)
}

const reverseLookupToolScript = `param(
  [string]$SharedDir,
  [string]$UserDir,
  [ValidateSet("full", "variable", "shorthand")]
  [string]$Mode = "variable"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Show-Error {
  param([string]$Message)
  [System.Windows.Forms.MessageBox]::Show($Message, "反查编码", "OK", "Error") | Out-Null
}

function Normalize-Pinyin {
  param([string]$Value)
  return $Value.Trim().ToLowerInvariant().Replace("u:", "ü").Replace("v", "ü")
}

function Split-CompactNumericPinyinToken {
  param([string]$Token)
  $tokenText = $Token.Trim()
  if ([string]::IsNullOrWhiteSpace($tokenText)) { return @() }

  $parts = New-Object System.Collections.Generic.List[string]
  $start = 0
  $sawToneDigit = $false
  for ($index = 0; $index -lt $tokenText.Length; $index++) {
    $char = $tokenText[$index]
    if ($char -notin @('1', '2', '3', '4', '5')) { continue }
    $sawToneDigit = $true
    if ($index -eq $start) { return @($tokenText) }
    $parts.Add($tokenText.Substring($start, $index - $start + 1))
    $start = $index + 1
  }
  if (-not $sawToneDigit -or $start -ne $tokenText.Length) { return @($tokenText) }
  return $parts.ToArray()
}

function Normalize-PinyinSpacing {
  param([string]$Value)
  $parts = New-Object System.Collections.Generic.List[string]
  foreach ($token in ($Value -split "\s+")) {
    if ([string]::IsNullOrWhiteSpace($token)) { continue }
    foreach ($part in (Split-CompactNumericPinyinToken $token)) {
      $normalized = Normalize-Pinyin $part
      if (-not [string]::IsNullOrWhiteSpace($normalized)) { $parts.Add($normalized) }
    }
  }
  return ($parts.ToArray() -join " ")
}

function Load-CodeMap {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { throw "找不到拼音编码表：$Path" }
  $map = @{}
  $lines = Get-Content -LiteralPath $Path -Encoding UTF8
  foreach ($line in $lines | Select-Object -Skip 1) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $fields = $line -split ([string][char]9)
    if ($fields.Count -ne 4) { continue }
    $key = Normalize-Pinyin $fields[0]
    $record = @{
      full = $fields[1]
      variable = $fields[2]
      shorthand = $fields[3]
    }
    $map[$key] = $record
    if ($key.Contains("ü")) {
      $map[$key.Replace("ü", "v")] = $record
      $map[$key.Replace("ü", "u:")] = $record
    }
  }
  return $map
}

function Load-DictLookup {
  param([string]$Path)
  $lookup = @{}
  if (-not (Test-Path -LiteralPath $Path)) { return $lookup }
  $inData = $false
  foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
    $trimmed = $line.Trim()
    if (-not $inData) {
      if ($trimmed -eq "...") { $inData = $true }
      continue
    }
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) { continue }
    $fields = $trimmed -split ([string][char]9)
    if ($fields.Count -lt 2) { continue }
    $text = $fields[0].Trim()
    $code = $fields[1].Trim()
    if ([string]::IsNullOrWhiteSpace($text) -or [string]::IsNullOrWhiteSpace($code)) { continue }
    if (-not $lookup.ContainsKey($text)) { $lookup[$text] = $code }
  }
  return $lookup
}

function Load-NumericToMarkedLookup {
  param([string]$Path)
  $lookup = @{}
  if (-not (Test-Path -LiteralPath $Path)) { return $lookup }
  try {
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($property in $raw.PSObject.Properties) {
      $key = Normalize-Pinyin $property.Name
      $value = [string]$property.Value
      if (-not [string]::IsNullOrWhiteSpace($key) -and -not [string]::IsNullOrWhiteSpace($value)) {
        $lookup[$key] = $value.Trim()
      }
    }
  } catch {
    return @{}
  }
  return $lookup
}

function Load-UserPhraseEntries {
  param([string]$Path)
  $entries = New-Object System.Collections.Generic.List[object]
  if (-not (Test-Path -LiteralPath $Path)) { return $entries }
  $lineNumber = 0
  foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
    $lineNumber++
    if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith("#")) { continue }
    $fields = $line -split ([string][char]9)
    if ($fields.Count -lt 2) { continue }
    $phrase = $fields[0].Trim()
    $pinyin = Normalize-PinyinSpacing $fields[1]
    if ([string]::IsNullOrWhiteSpace($phrase) -or [string]::IsNullOrWhiteSpace($pinyin)) { continue }
    $entries.Add([pscustomobject]@{
      Phrase = $phrase
      Pinyin = $pinyin
    })
  }
  return $entries
}

function Get-SchemaIDFromMode {
  param([string]$ModeValue)
  switch ($ModeValue) {
    "full" { return "yime_full" }
    "shorthand" { return "yime_shorthand" }
    default { return "yime_variable" }
  }
}

function Get-CodeColumnFromMode {
  param([string]$ModeValue)
  switch ($ModeValue) {
    "full" { return "full" }
    "shorthand" { return "shorthand" }
    default { return "variable" }
  }
}

function Build-ReverseCodeLookup {
  param(
    [hashtable]$CodeMap,
    [string]$Column
  )
  $lookup = @{}
  foreach ($numeric in $CodeMap.Keys) {
    $record = $CodeMap[$numeric]
    $code = [string]$record[$Column]
    if (-not [string]::IsNullOrWhiteSpace($code) -and -not $lookup.ContainsKey($code)) {
      $lookup[$code] = $numeric
    }
  }
  return $lookup
}

function Split-YimeCodeToNumericPinyin {
  param(
    [string]$Code,
    [hashtable]$ReverseLookup
  )
  $codeText = $Code.Trim()
  if ([string]::IsNullOrWhiteSpace($codeText)) { return $null }

  $parts = New-Object System.Collections.Generic.List[string]
  $index = 0
  while ($index -lt $codeText.Length) {
    $matched = $false
    for ($end = $codeText.Length; $end -gt $index; $end--) {
      $segment = $codeText.Substring($index, $end - $index)
      if (-not $ReverseLookup.ContainsKey($segment)) { continue }
      $parts.Add($ReverseLookup[$segment])
      $index = $end
      $matched = $true
      break
    }
    if (-not $matched) { return $null }
  }
  return $parts.ToArray()
}

function Join-CharCodeLookup {
  param(
    [string]$Text,
    [hashtable]$Lookup,
    [string]$Separator = ""
  )
  $parts = New-Object System.Collections.Generic.List[string]
  foreach ($char in $Text.ToCharArray()) {
    $key = [string]$char
    if (-not $Lookup.ContainsKey($key)) { return "" }
    $parts.Add($Lookup[$key])
  }
  return ($parts.ToArray() -join $Separator)
}

function Get-MarkedVowelIndex {
  param([char[]]$Syllable)
  for ($i = 0; $i -lt $Syllable.Length; $i++) {
    if ($Syllable[$i] -eq 'a' -or $Syllable[$i] -eq 'e') { return $i }
  }
  for ($i = 0; $i -lt $Syllable.Length - 1; $i++) {
    if ($Syllable[$i] -eq 'o' -and $Syllable[$i + 1] -eq 'u') { return $i }
  }
  for ($i = $Syllable.Length - 1; $i -ge 0; $i--) {
    if ($Syllable[$i] -in @('a', 'e', 'i', 'o', 'u', 'ü')) { return $i }
  }
  return -1
}

function Convert-AccentVowel {
  param(
    [char]$Vowel,
    [int]$Tone
  )
  switch ($Vowel) {
    'a' { return @('a', 'ā', 'á', 'ǎ', 'à')[$Tone] }
    'e' { return @('e', 'ē', 'é', 'ě', 'è')[$Tone] }
    'i' { return @('i', 'ī', 'í', 'ǐ', 'ì')[$Tone] }
    'o' { return @('o', 'ō', 'ó', 'ǒ', 'ò')[$Tone] }
    'u' { return @('u', 'ū', 'ú', 'ǔ', 'ù')[$Tone] }
    'ü' { return @('ü', 'ǖ', 'ǘ', 'ǚ', 'ǜ')[$Tone] }
    default { return $Vowel }
  }
}

function Convert-NumericSyllableToMarked {
  param([string]$Syllable)
  $normalized = Normalize-Pinyin $Syllable
  if ([string]::IsNullOrWhiteSpace($normalized)) { return "" }
  $chars = $normalized.ToCharArray()
  $last = $chars[$chars.Length - 1]
  if ($last -lt '1' -or $last -gt '5') { return $normalized }
  $tone = [int][string]$last
  if ($tone -eq 5 -or $chars.Length -lt 2) {
    if ($chars.Length -lt 2) { return $normalized }
    return -join $chars[0..($chars.Length - 2)]
  }
  $base = $chars[0..($chars.Length - 2)]
  $index = Get-MarkedVowelIndex $base
  if ($index -lt 0) { return -join $base }
  $base[$index] = Convert-AccentVowel $base[$index] $tone
  return -join $base
}

function Convert-NumericPinyinToMarked {
  param(
    [string]$NumericPinyin,
    [hashtable]$MarkedLookup
  )
  $parts = @()
  foreach ($token in (($NumericPinyin -split "\s+") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
    $normalized = Normalize-Pinyin $token
    if ([string]::IsNullOrWhiteSpace($normalized)) { continue }
    if ($MarkedLookup.ContainsKey($normalized)) {
      $parts += $MarkedLookup[$normalized]
    } else {
      $parts += Convert-NumericSyllableToMarked $normalized
    }
  }
  return ($parts -join " ")
}

function Convert-PinyinToCode {
  param(
    [hashtable]$CodeMap,
    [string]$Pinyin,
    [string]$Column
  )
  $normalized = Normalize-PinyinSpacing $Pinyin
  if ([string]::IsNullOrWhiteSpace($normalized)) { return "" }
  $builder = New-Object System.Text.StringBuilder
  foreach ($item in ($normalized -split "\s+")) {
    if (-not $CodeMap.ContainsKey($item)) { return "" }
    [void]$builder.Append($CodeMap[$item][$Column])
  }
  return $builder.ToString()
}

function Build-LookupResult {
  param(
    [string]$Phrase,
    [string]$Source,
    [string]$NumericPinyin,
    [string]$YimeCode,
    [hashtable]$CodeMap,
    [hashtable]$ReverseLookup,
    [hashtable]$MarkedLookup,
    [string]$ActiveColumn
  )

  $code = $YimeCode
  $numeric = $NumericPinyin
  if ([string]::IsNullOrWhiteSpace($numeric) -and -not [string]::IsNullOrWhiteSpace($code)) {
    $decoded = Split-YimeCodeToNumericPinyin $code $ReverseLookup
    if ($null -ne $decoded -and $decoded.Count -gt 0) {
      $numeric = ($decoded -join " ")
    }
  }
  if ([string]::IsNullOrWhiteSpace($code) -and -not [string]::IsNullOrWhiteSpace($numeric)) {
    $code = Convert-PinyinToCode $CodeMap $numeric $ActiveColumn
  }

  $fullCode = ""
  $variableCode = ""
  $shorthandCode = ""
  if (-not [string]::IsNullOrWhiteSpace($numeric)) {
    $fullCode = Convert-PinyinToCode $CodeMap $numeric "full"
    $variableCode = Convert-PinyinToCode $CodeMap $numeric "variable"
    $shorthandCode = Convert-PinyinToCode $CodeMap $numeric "shorthand"
  } elseif (-not [string]::IsNullOrWhiteSpace($code)) {
    $fullCode = $code
    $variableCode = $code
    $shorthandCode = $code
  }

  $activeCode = switch ($ActiveColumn) {
    "full" { $fullCode }
    "shorthand" { $shorthandCode }
    default { $variableCode }
  }
  if ([string]::IsNullOrWhiteSpace($activeCode)) { $activeCode = $code }

  return [pscustomobject]@{
    Phrase = $Phrase
    Source = $Source
    NumericPinyin = $numeric
    StandardPinyin = (Convert-NumericPinyinToMarked $numeric $MarkedLookup)
    ActiveCode = $activeCode
    FullCode = $fullCode
    VariableCode = $variableCode
    ShorthandCode = $shorthandCode
  }
}

function Resolve-PhraseLookup {
  param(
    [string]$Phrase,
    [System.Collections.IEnumerable]$UserEntries,
    [hashtable]$DictLookup,
    [hashtable]$CodeMap,
    [hashtable]$ReverseLookup,
    [hashtable]$MarkedLookup,
    [string]$ActiveColumn
  )

  $text = $Phrase.Trim()
  if ([string]::IsNullOrWhiteSpace($text)) { return $null }

  foreach ($entry in $UserEntries) {
    if ($entry.Phrase -eq $text) {
      return Build-LookupResult $text "用户词库" $entry.Pinyin "" $CodeMap $ReverseLookup $MarkedLookup $ActiveColumn
    }
  }

  $yimeCode = ""
  $source = ""
  if ($DictLookup.ContainsKey($text)) {
    $yimeCode = $DictLookup[$text]
    $source = "系统词库"
  } else {
    $joined = Join-CharCodeLookup $text $DictLookup ""
    if (-not [string]::IsNullOrWhiteSpace($joined)) {
      $yimeCode = $joined
      $source = "逐字拼接"
    }
  }

  if ([string]::IsNullOrWhiteSpace($yimeCode)) { return $null }
  return Build-LookupResult $text $source "" $yimeCode $CodeMap $ReverseLookup $MarkedLookup $ActiveColumn
}

function Search-ReverseLookup {
  param(
    [string]$Term,
    [bool]$ContainsMatch,
    [System.Collections.IEnumerable]$UserEntries,
    [hashtable]$DictLookup,
    [hashtable]$CodeMap,
    [hashtable]$ReverseLookup,
    [hashtable]$MarkedLookup,
    [string]$ActiveColumn
  )

  $text = $Term.Trim()
  if ([string]::IsNullOrWhiteSpace($text)) { return @() }

  $results = New-Object System.Collections.Generic.List[object]
  $seen = @{}

  function Add-Result {
    param($Item)
    if ($null -eq $Item) { return }
    if ($seen.ContainsKey($Item.Phrase)) { return }
    $seen[$Item.Phrase] = $true
    $results.Add($Item)
  }

  Add-Result (Resolve-PhraseLookup $text $UserEntries $DictLookup $CodeMap $ReverseLookup $MarkedLookup $ActiveColumn)
  if ($results.Count -gt 0 -and -not $ContainsMatch) { return $results.ToArray() }

  foreach ($entry in $UserEntries) {
    if ($results.Count -ge 100) { break }
    if ($entry.Phrase -eq $text) { continue }
    if ($ContainsMatch) {
      if ($entry.Phrase -notlike ("*" + $text + "*")) { continue }
    } else {
      continue
    }
    Add-Result (Resolve-PhraseLookup $entry.Phrase $UserEntries $DictLookup $CodeMap $ReverseLookup $MarkedLookup $ActiveColumn)
  }

  if ($ContainsMatch) {
    foreach ($phrase in $DictLookup.Keys) {
      if ($results.Count -ge 100) { break }
      if ($seen.ContainsKey($phrase)) { continue }
      if ($phrase -notlike ("*" + $text + "*")) { continue }
      Add-Result (Resolve-PhraseLookup $phrase $UserEntries $DictLookup $CodeMap $ReverseLookup $MarkedLookup $ActiveColumn)
    }
  }

  return $results.ToArray()
}

$script:lookupLoaded = $false
$script:codeMap = $null
$script:dictLookup = $null
$script:userEntries = $null
$script:markedLookup = $null
$script:reverseLookup = $null
$script:activeColumn = Get-CodeColumnFromMode $Mode

$form = New-Object System.Windows.Forms.Form
$form.Text = "Yime 反查编码"
$form.StartPosition = "CenterScreen"
$form.ClientSize = New-Object System.Drawing.Size(920, 560)
$form.MinimumSize = New-Object System.Drawing.Size(760, 480)

$searchLabel = New-Object System.Windows.Forms.Label
$searchLabel.Left = 12
$searchLabel.Top = 14
$searchLabel.Width = 72
$searchLabel.Text = "查询词条"
$form.Controls.Add($searchLabel)

$searchBox = New-Object System.Windows.Forms.TextBox
$searchBox.Left = 88
$searchBox.Top = 10
$searchBox.Width = 360
$form.Controls.Add($searchBox)

$containsCheckBox = New-Object System.Windows.Forms.CheckBox
$containsCheckBox.Left = 456
$containsCheckBox.Top = 12
$containsCheckBox.Width = 96
$containsCheckBox.Text = "包含匹配"
$form.Controls.Add($containsCheckBox)

$modeLabel = New-Object System.Windows.Forms.Label
$modeLabel.Left = 568
$modeLabel.Top = 14
$modeLabel.Width = 40
$modeLabel.Text = "方案"
$form.Controls.Add($modeLabel)

$modeComboBox = New-Object System.Windows.Forms.ComboBox
$modeComboBox.Left = 612
$modeComboBox.Top = 10
$modeComboBox.Width = 120
$modeComboBox.DropDownStyle = "DropDownList"
[void]$modeComboBox.Items.Add([pscustomobject]@{ Label = "变长"; Value = "variable" })
[void]$modeComboBox.Items.Add([pscustomobject]@{ Label = "等长"; Value = "full" })
[void]$modeComboBox.Items.Add([pscustomobject]@{ Label = "省键"; Value = "shorthand" })
$modeComboBox.DisplayMember = "Label"
$modeComboBox.ValueMember = "Value"
$form.Controls.Add($modeComboBox)

$searchButton = New-Object System.Windows.Forms.Button
$searchButton.Left = 744
$searchButton.Top = 8
$searchButton.Width = 80
$searchButton.Text = "查询"
$form.Controls.Add($searchButton)

$listView = New-Object System.Windows.Forms.ListView
$listView.Left = 12
$listView.Top = 44
$listView.Width = 896
$listView.Height = 460
$listView.View = "Details"
$listView.FullRowSelect = $true
$listView.GridLines = $true
$listView.MultiSelect = $false
[void]$listView.Columns.Add("词条", 96)
[void]$listView.Columns.Add("来源", 88)
[void]$listView.Columns.Add("数字标调", 160)
[void]$listView.Columns.Add("标准拼音", 160)
[void]$listView.Columns.Add("当前编码", 120)
[void]$listView.Columns.Add("全码", 96)
[void]$listView.Columns.Add("变长", 96)
[void]$listView.Columns.Add("省键", 96)
$form.Controls.Add($listView)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Left = 12
$statusLabel.Top = 512
$statusLabel.Width = 896
$statusLabel.Height = 36
$statusLabel.Text = "输入字词后点击【查询】，可查看标准拼音、数字标调与音元编码。"
$form.Controls.Add($statusLabel)

function Ensure-LookupData {
  if ($script:lookupLoaded) { return }
  $codeMapPath = Join-Path $SharedDir "yime_pinyin_codes.tsv"
  $markedPath = Join-Path $SharedDir "pinyin_normalized.json"
  $userPhrasePath = Join-Path $UserDir "yime_user_phrases.txt"
  $schemaID = Get-SchemaIDFromMode ([string]$modeComboBox.SelectedItem.Value)
  $dictPath = Join-Path $SharedDir ($schemaID + ".dict.yaml")

  $script:codeMap = Load-CodeMap $codeMapPath
  $script:markedLookup = Load-NumericToMarkedLookup $markedPath
  $script:userEntries = Load-UserPhraseEntries $userPhrasePath
  $script:dictLookup = Load-DictLookup $dictPath
  $script:activeColumn = Get-CodeColumnFromMode ([string]$modeComboBox.SelectedItem.Value)
  $script:reverseLookup = Build-ReverseCodeLookup $script:codeMap $script:activeColumn
  $script:lookupLoaded = $true
}

function Refresh-ResultList {
  param([string]$Term)
  Ensure-LookupData
  $listView.Items.Clear()
  $results = Search-ReverseLookup $Term $containsCheckBox.Checked $script:userEntries $script:dictLookup $script:codeMap $script:reverseLookup $script:markedLookup $script:activeColumn

  foreach ($item in $results) {
    $row = New-Object System.Windows.Forms.ListViewItem($item.Phrase)
    [void]$row.SubItems.Add($item.Source)
    [void]$row.SubItems.Add($item.NumericPinyin)
    [void]$row.SubItems.Add($item.StandardPinyin)
    [void]$row.SubItems.Add($item.ActiveCode)
    [void]$row.SubItems.Add($item.FullCode)
    [void]$row.SubItems.Add($item.VariableCode)
    [void]$row.SubItems.Add($item.ShorthandCode)
    [void]$listView.Items.Add($row)
  }

  if ($results.Count -eq 0) {
    $statusLabel.Text = "未找到匹配结果。可勾选【包含匹配】在用户词库和系统词库中模糊搜索。"
  } else {
    $statusLabel.Text = ("找到 {0} 条结果。当前方案列显示的是所选编码方案。" -f $results.Count)
  }
}

function Invoke-Search {
  $term = $searchBox.Text.Trim()
  if ([string]::IsNullOrWhiteSpace($term)) {
    Show-Error "请输入要查询的字词。"
    return
  }
  try {
    $script:lookupLoaded = $false
    Refresh-ResultList $term
  } catch {
    Show-Error $_.Exception.Message
  }
}

$searchButton.Add_Click({
  try { Invoke-Search } catch { Show-Error $_.Exception.Message }
})

$searchBox.Add_KeyDown({
  param($sender, $eventArgs)
  if ($eventArgs.KeyCode -eq "Enter") {
    $eventArgs.SuppressKeyPress = $true
    try { Invoke-Search } catch { Show-Error $_.Exception.Message }
  }
})

$modeComboBox.Add_SelectedIndexChanged({
  try {
    if ($modeComboBox.SelectedItem) {
      $script:activeColumn = Get-CodeColumnFromMode ([string]$modeComboBox.SelectedItem.Value)
      if ($script:codeMap) {
        $script:reverseLookup = Build-ReverseCodeLookup $script:codeMap $script:activeColumn
      }
      if (-not [string]::IsNullOrWhiteSpace($searchBox.Text.Trim())) {
        Refresh-ResultList $searchBox.Text.Trim()
      }
    }
  } catch {
    Show-Error $_.Exception.Message
  }
})

$form.Add_Shown({
  try {
    $screenBounds = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $x = $screenBounds.Left + [int](($screenBounds.Width - $form.Width) / 2)
    $y = $screenBounds.Top + [int](($screenBounds.Height - $form.Height) / 2)
    if ($x -lt $screenBounds.Left) { $x = $screenBounds.Left }
    if ($y -lt $screenBounds.Top) { $y = $screenBounds.Top }
    $form.Location = New-Object System.Drawing.Point($x, $y)

    foreach ($item in $modeComboBox.Items) {
      if ($item.Value -eq $Mode) {
        $modeComboBox.SelectedItem = $item
        break
      }
    }
    if ($null -eq $modeComboBox.SelectedItem) {
      $modeComboBox.SelectedIndex = 0
    }

    $form.BeginInvoke([System.Windows.Forms.MethodInvoker]{
      try {
        Ensure-LookupData
        $statusLabel.Text = "数据已加载。输入字词后点击【查询】。"
      } catch {
        Show-Error $_.Exception.Message
      }
    }) | Out-Null
  } catch {
    Show-Error $_.Exception.Message
  }
})

try {
  [void]$form.ShowDialog()
} catch {
  Show-Error $_.Exception.Message
}
`

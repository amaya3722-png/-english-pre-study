# Pre-study MD → HTML builder
param($Day, $Slot)

$vault = "$env:USERPROFILE\Documents\Obsidian Vault\EnglishLearning"
$mdFile = "$vault\06-Prompts\Day$Day\$Slot.md"
$outDir = "$vault\07-Pages\day$Day"
$outFile = "$outDir\$Slot.html"

if (-not (Test-Path $mdFile)) { Write-Output "ERR: $mdFile not found"; exit 1 }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$raw = Get-Content $mdFile -Raw -Encoding UTF8

# ── Extract sections ──
# Split on "## 🤖" to separate pre-study from coach prompt
$parts = $raw -split '(?=## 🤖)'
$studyPart = if ($parts.Length -ge 2) { $parts[0] } else { $raw }
$coachPart = if ($parts.Length -ge 2) { $parts[1] } else { "" }

# ── Parse pre-study metadata ──
$title = ""
$subtitle = ""
$eyebrow = ""

if ($studyPart -match '### Model Answer.*?\n\n\*\*Question:\s*"([^"]+)"') { $title = $matches[1] }
if ($studyPart -match '^\*\*Question:\s*"([^"]+)"') { $title = $matches[1] }
if (-not $title) {
    if ($studyPart -match '^## 📚 预学材料[^\n]*\n\n([^\n]+)') { $title = $matches[1] }
}

# Day and slot info
$dayLabel = "Day $Day"
$timeLabel = "$($Slot.Substring(0,2)):$($Slot.Substring(2,2))"

# ── Helper: md inline → html ──
function Convert-MdInline($text) {
    $t = $text
    $t = $t -replace '\*\*(.+?)\*\*', '<strong>$1</strong>'
    $t = $t -replace '\*(.+?)\*', '<em>$1</em>'
    $t = $t -replace '`([^`]+)`', '<code>$1</code>'
    return $t
}

# ── Build vocab cards from table ──
$vocabCards = ""
$inVocab = $false
$lines = $studyPart -split "`n"
for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i].Trim()
    if ($line -match '^\| \*\*(.+?)\*\* \| (.+?) \| (.+?) \|$' -and $line -notmatch 'Chunk|画面|发音|---') {
        $chunk = $matches[1]
        $scene = $matches[2]
        $pron = $matches[3]
        $vocabCards += @"
<div class="vocab-card">
  <div class="chunk">$chunk</div>
  <div class="pron">🔊 $pron</div>
  <div class="scene">$scene</div>
</div>
"@
    }
}

# ── Extract grammar tables ──
$grammarHTML = ""
$inGrammar = $false
$wrongCol = @()
$rightCol = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i].Trim()
    if ($line -match '^\| ❌ (.+?) \| ✅ (.+?) \|$') {
        $wrongCol += $matches[1]
        $rightCol += $matches[2]
    }
}
if ($wrongCol.Count -gt 0) {
    $rows = ""
    for ($j = 0; $j -lt $wrongCol.Count; $j++) {
        $w = Convert-MdInline $wrongCol[$j]
        $r = Convert-MdInline $rightCol[$j]
        $rows += "<tr><td class='wrong'>$w</td><td class='right'>$r</td></tr>`n"
    }
    $grammarHTML = "<table><tr><th>❌ 常见错误</th><th>✅ 正确表达</th></tr>$rows</table>"
}

# ── Extract pronunciation items ──
$pronItems = ""
$inPron = $false
for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i].Trim()
    if ($line -match '^\*\*(.+?)\*\* — (.+)$') {
        $word = $matches[1]
        $note = Convert-MdInline $matches[2]
        $pronItems += "<div class='pron-item'><strong>$word</strong> → $note</div>`n"
    }
    if ($line -match '^- \*\*(.+?)\*\*[—–-]\s*(.+)$') {
        $word = $matches[1]
        $note = Convert-MdInline $matches[2]
        $pronItems += "<div class='pron-item'><strong>$word</strong> → $note</div>`n"
    }
}

# ── Extract model answer ──
$modelAnswer = ""
$inModel = $false
$qaLabel = ""
$modelLines = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    if ($line -match '^\*\*Question:\s*"(.+)"\*\*') {
        $qaLabel = $matches[1]
        $inModel = $true
        continue
    }
    if ($inModel -and $line.Trim() -eq '---') { $inModel = $false; continue }
    if ($inModel -and $line.Trim() -eq '') { continue }
    if ($inModel -and $line.Trim() -match '^> (.+)') {
        $modelLines += Convert-MdInline $matches[1]
        continue
    }
    if ($inModel -and $line.Trim() -ne '' -and $line.Trim() -notmatch '^(###|##|\*\*)') {
        $modelLines += Convert-MdInline $line.Trim()
    }
}
if ($qaLabel) {
    $modelAnswer = "<div class='model-answer'><div class='qa-label'>📋 $qaLabel</div>"
    foreach ($ml in $modelLines) { $modelAnswer += "<p>$ml</p>" }
    $modelAnswer += "</div>"
}

# ── Extract mnemonic ──
$mnemonic = ""
if ($studyPart -match '\*\*口诀[：:]\*\*\s*(.+?)(?:\n|$)') {
    $mnemonic = "<div class='mnemonic'>$($matches[1])</div>"
}

# ── Extract checklist items ──
$checklistItems = ""
$inChecklist = $false
for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i].Trim()
    if ($line -match '^- \[ \] (.+)$') {
        $checklistItems += "<li>$($matches[1])</li>`n"
    }
}

# ── Clean coach part for display ──
$coachDisplay = $coachPart -replace '## 🤖 教练 Prompt.*?\n', ''
$coachDisplay = $coachDisplay.Trim()
$coachDisplay = [System.Net.WebUtility]::HtmlEncode($coachDisplay)

# ── Assemble HTML ──
$html = @"
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$title — $dayLabel · $timeLabel</title>
<link rel="stylesheet" href="../css/style.css">
</head>
<body>

<header class="topbar">
  <span class="brand">◆ 三脑英语</span>
  <span class="meta">$dayLabel · $timeLabel · 面试特训 Week 1</span>
</header>

<div class="hero">
  <div class="eyebrow">Pre-Study Package · 课前预学</div>
  <h1>$title</h1>
  <div class="subtitle">智能终端产品线转型 · STAR Method</div>
  <div class="time-block">
    <span class="pill">📚 自学 15 min</span>
    <span class="pill">🎤 口语课 25 min</span>
    <span class="pill">📅 $dayLabel</span>
  </div>
</div>

<div class="container">

  <!-- Model Answer -->
  <div class="section">
    <h2><span class="icon">📋</span> Model Answer（B2 级理想回答）</h2>
    $modelAnswer
  </div>

  <!-- Vocabulary Cards -->
  <div class="section">
    <h2><span class="icon">📝</span> 词汇卡片 · Chunk + 画面 + 发音</h2>
    <div class="vocab-grid">
      $vocabCards
    </div>
  </div>

  <!-- Grammar Anchor -->
  <div class="section">
    <h2><span class="icon">🎯</span> 语法锚点</h2>
    <div class="grammar-box">
      $grammarHTML
      $mnemonic
    </div>
  </div>

  <!-- Pronunciation -->
  <div class="section">
    <h2><span class="icon">🔊</span> 发音预警</h2>
    <div class="pron-alert">
      $pronItems
    </div>
  </div>

  <!-- Retrieval Checklist -->
  <div class="section">
    <h2><span class="icon">🧠</span> 检索练习 · Retrieval Practice</h2>
    <p style="color:var(--muted);font-size:14px;margin-bottom:16px;">⚠️ 关键步骤：合上一切 → 录音 → 自己说一遍 → 听录音 → 只练最卡的那 1 处</p>
    <ol class="checklist">
      $checklistItems
    </ol>
  </div>

  <!-- Coach Prompt -->
  <div class="coach-divider">▼ 自学完成后 · 复制以下 Prompt 发给 GPT/豆包 ▼</div>

  <div class="section">
    <h2><span class="icon">🤖</span> Coach Prompt</h2>
    <p style="font-size:14px;color:var(--muted);margin-bottom:12px;">👉 点击下方文本框自动全选，复制后打开 GPT/豆包语音模式粘贴</p>
    <div class="coach-prompt" onclick="this.select();document.execCommand('copy');this.style.background='#e8f5e9';setTimeout(()=>this.style.background='#f8faf9',800);" title="点击复制">$coachDisplay</div>
  </div>

</div>

<script>
// Click-to-copy for the coach prompt block
document.querySelector('.coach-prompt').addEventListener('click', function() {
  const text = this.textContent;
  navigator.clipboard.writeText(text).then(() => {
    this.style.background = '#e8f5e9';
    setTimeout(() => { this.style.background = '#f8faf9'; }, 800);
  });
});
</script>

</body>
</html>
"@

# Write output
[System.IO.File]::WriteAllText($outFile, $html, [System.Text.UTF8Encoding]::new($false))
Write-Output "OK: $outFile"

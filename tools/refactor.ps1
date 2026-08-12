$ErrorActionPreference = 'Stop'
$tools = $PSScriptRoot
$utf8  = New-Object System.Text.UTF8Encoding $false

foreach ($f in Get-ChildItem "$tools\body-*.html") {
  $s = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
  $orig = $s

  # --- 1. Drop text-justify everywhere, then restore it on the hero lead only ---
  $s = $s -replace '\s+text-justify(?=["\s])', ''
  $s = $s -replace 'class="text-justify"', 'class=""'
  $s = $s -replace ' class=""', ''
  $i = $s.IndexOf('<p class="lead')
  if ($i -ge 0) { $s = $s.Substring(0, $i) + '<p class="lead text-justify' + $s.Substring($i + 14) }

  # --- 2. Labelled <ul class="checks"> -> <dl class="row deflist g-0"> ---
  $ulRx = [regex]'(?s)<ul class="checks"(?<attr>[^>]*)>(?<inner>.*?)</ul>'
  $liRx = [regex]'(?s)<li>(?<body>.*?)</li>'
  $stRx = [regex]'(?s)^\s*<strong>(?<term>.*?)</strong>\s*(?<desc>.*?)\s*$'

  $s = $ulRx.Replace($s, {
    param($m)
    $items = $liRx.Matches($m.Groups['inner'].Value)
    if ($items.Count -eq 0) { return $m.Value }
    $pairs = @()
    foreach ($it in $items) {
      $sm = $stRx.Match($it.Groups['body'].Value)
      if (-not $sm.Success) { return $m.Value }   # plain bullet list: leave alone
      $term = $sm.Groups['term'].Value.Trim() -replace '\.$', ''
      $desc = $sm.Groups['desc'].Value.Trim() -replace '^(&mdash;|—)\s*', ''
      if ($desc.Length -gt 0) { $desc = $desc.Substring(0,1).ToUpper() + $desc.Substring(1) }
      $pairs += ('    <dt class="col-sm-5">' + $term + '</dt>' + "`n" +
                 '    <dd class="col-sm-7">' + $desc + '</dd>')
    }
    return '<dl class="row deflist g-0">' + "`n" + ($pairs -join "`n") + "`n" + '  </dl>'
  })

  if ($s -ne $orig) {
    [System.IO.File]::WriteAllText($f.FullName, $s, $utf8)
    $dl = ([regex]::Matches($s, 'class="row deflist')).Count
    $tj = ([regex]::Matches($s, 'text-justify')).Count
    Write-Output ("{0,-24} deflists={1,-3} text-justify={2}" -f $f.Name, $dl, $tj)
  } else {
    Write-Output ("{0,-24} unchanged" -f $f.Name)
  }
}

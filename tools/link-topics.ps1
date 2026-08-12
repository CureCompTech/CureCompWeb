<#
  Points every call-to-action at the matching subject in the contact form.
  contact.html reads ?topic=<slug> and preselects the dropdown (see main.js).
  Re-runnable: links that already carry a topic are left alone.
#>
$ErrorActionPreference = 'Stop'
$tools = $PSScriptRoot
$utf8  = New-Object System.Text.UTF8Encoding $false

# Buttons whose label implies a more specific subject than the page default.
$specific = @{
  'body-cloud.html' = @(
    @{ label = 'Quote a dedicated server'; topic = 'cloud-dedicated' },
    @{ label = 'Quote colocation';         topic = 'cloud-colocation' },
    @{ label = 'Quote VM / LXC';           topic = 'cloud-vm' },
    @{ label = 'Discuss IPv6 allocation';  topic = 'cloud-ipv6' }
  )
}

# Fallback subject for every remaining bare contact.html link on that page.
$defaults = @{
  'body-shop.html'       = 'hardware'
  'body-managed-it.html' = 'msp'
  'body-network.html'    = 'networking'
  'body-cloud.html'      = 'cloud'
  'body-pon-stick.html'  = 'pon-stick'
  # index and about stay generic: they are overviews, not a single subject.
}

foreach ($name in ($specific.Keys + $defaults.Keys | Select-Object -Unique)) {
  $path = Join-Path $tools $name
  if (-not (Test-Path $path)) { throw "missing fragment: $name" }
  $s = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
  $before = $s

  if ($specific.ContainsKey($name)) {
    foreach ($b in $specific[$name]) {
      $s = $s.Replace(
        'href="contact.html">' + $b.label,
        'href="contact.html?topic=' + $b.topic + '#enquiry">' + $b.label)
    }
  }

  if ($defaults.ContainsKey($name)) {
    $s = $s.Replace('href="contact.html"', 'href="contact.html?topic=' + $defaults[$name] + '#enquiry"')
  }

  if ($s -ne $before) {
    [System.IO.File]::WriteAllText($path, $s, $utf8)
  }
  $n = ([regex]::Matches($s, 'contact\.html\?topic=')).Count
  $bare = ([regex]::Matches($s, 'contact\.html"')).Count
  Write-Output ("{0,-24} topic links={1,-3} bare contact links={2}" -f $name, $n, $bare)
}

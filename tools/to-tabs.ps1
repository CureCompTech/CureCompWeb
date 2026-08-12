<#
	Converts leading-space indentation to tabs across the site sources.

	Only the run of whitespace at the START of each line is touched, so spaces
	inside text, attributes, CSS values and data: URIs are left exactly as they
	are. Two spaces = one tab, matching the indent step the files were written
	with; an odd leftover space is dropped so levels stay clean.

	Lines already indented with tabs are left alone, which makes this safe to
	re-run.

		powershell -ExecutionPolicy Bypass -File tools\to-tabs.ps1
#>

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$utf8 = New-Object System.Text.UTF8Encoding $false

$targets = @(
	(Join-Path $root 'tools\_layout.html')
	(Get-ChildItem (Join-Path $root 'tools\body-*.html') | ForEach-Object { $_.FullName })
	(Join-Path $root 'assets\css\theme.css')
	(Join-Path $root 'assets\js\main.js')
	(Join-Path $root '.claude\launch.json')
) | ForEach-Object { $_ } | Where-Object { Test-Path $_ }

foreach ($path in $targets) {
	$text  = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
	$eol   = if ($text -match "`r`n") { "`r`n" } else { "`n" }
	$lines = $text -split "`r?`n"
	$converted = 0

	for ($i = 0; $i -lt $lines.Count; $i++) {
		$m = [regex]::Match($lines[$i], '^(?<ws>[ ]+)(?<rest>.*)$')
		if (-not $m.Success) { continue }
		$spaces = $m.Groups['ws'].Value.Length
		$tabs   = [math]::Floor($spaces / 2)
		if ($tabs -lt 1) { continue }
		$lines[$i] = ("`t" * $tabs) + $m.Groups['rest'].Value
		$converted++
	}

	[System.IO.File]::WriteAllText($path, ($lines -join $eol), $utf8)
	$name = $path.Replace($root + '\', '')
	Write-Output ("{0,-34} {1,4} lines re-indented" -f $name, $converted)
}

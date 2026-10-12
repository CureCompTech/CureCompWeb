<#
	Assembles the static pages from tools/_layout.html + tools/body-*.html,
	and writes sitemap.xml and robots.txt.

	The published site is plain static HTML with no build step; this script only
	exists so the shared head, header and footer live in one file instead of
	eight copies. Run it after editing the layout or any body fragment:

			powershell -ExecutionPolicy Bypass -File tools\build.ps1

	All file I/O is done with UTF8Encoding($false) — Get-Content/Set-Content in
	Windows PowerShell 5.1 default to the ANSI codepage and will mangle the
	em dashes and other non-ASCII characters in the copy.

	NOTE: this file must keep its UTF-8 BOM. Windows PowerShell 5.1 reads a
	BOM-less .ps1 as ANSI and corrupts the non-ASCII characters below.
#>

$ErrorActionPreference = 'Stop'

# Self-check: if this file lost its UTF-8 BOM, Windows PowerShell 5.1 decodes it
# as ANSI and every em dash below silently becomes three junk characters that
# then get baked into the published pages. Fail loudly instead.
if ('—' -ne [string][char]0x2014) {
	throw 'build.ps1 was parsed as ANSI — re-save it as UTF-8 WITH BOM, then run again.'
}

# ---------------------------------------------------------------------------
# CHANGE THIS to the live domain before publishing. It is the only place the
# absolute URL appears; canonical links, Open Graph tags, Twitter cards,
# structured data and the sitemap are all derived from it. Social networks
# will not fetch a preview image from a relative path, so it must be absolute
# and must end with a trailing slash.
# ---------------------------------------------------------------------------
$siteUrl = 'https://curecomp.com.my/'

# ---------------------------------------------------------------------------
# Other domains that serve this same site. They are NOT given their own
# canonical URLs on purpose: three domains serving identical pages is duplicate
# content, and pointing each at itself would split the ranking signal three
# ways. Every page keeps one canonical (above) whichever domain served it, so
# links and authority from all three consolidate onto the primary.
#
# These are declared in the Organization's sameAs so Google associates the
# domains with the same business rather than treating them as strangers.
# See README for the redirect rules that make this airtight.
# ---------------------------------------------------------------------------
$altDomains = @(
	'https://curecomp.my/'
	'https://curecomp.pro/'
)

$root  = Split-Path -Parent $PSScriptRoot
$tools = Join-Path $root 'tools'
$utf8  = New-Object System.Text.UTF8Encoding $false

# ---------------------------------------------------------------------------
# Version stamping, so an upload is never hidden behind a cache.
#
# Cloudflare (and every browser) keys its cache on the full URL including the
# query string, so a new token in the URL forces a fresh fetch. The build
# stamps two kinds of URL:
#
#   Assets  Every local reference to a file under assets/ — stylesheet,
#           script, logos, icons, the social preview image — gets
#           ?v=<token for that file>. Cloudflare holds these for 4 hours at
#           the edge and in browsers, so an unstamped logo would stay stale.
#
#   Pages   Every link to another page gets ?v=<build token>. It is ONE token
#           for the whole build, deliberately not one per page: every page
#           carries the full navigation, so changing any page changes the
#           links inside all the others. With per-page tokens an old cached
#           copy of page A (unchanged URL) would still point at the old copy
#           of page B. One build-wide token moves every page to a fresh URL at
#           once whenever anything changed, and stays the same when a rebuild
#           changed nothing, so caches stay warm. Canonical links, og:url,
#           structured data and the sitemap always stay clean.
#
# Token modes:
#   'hash'   default. A short SHA-256 of the content, e.g. v=6f2a91c0d4 —
#            per file for assets, over the whole site for the build token.
#            Changes if and only if something actually changed. Nothing to
#            remember.
#   'commit' the short git commit of HEAD, e.g. commit=36fe14c. Note this is
#            HEAD at BUILD time, so it names the commit before the one that
#            carries the rebuilt pages.
#   'manual' the fixed string in $assetVersionValue, e.g. version=1.1. You
#            must remember to bump it, or visitors keep the stale file.
#
# Each page also records when its own content last changed, in
# tools/versions.json (commit it). That date is shown in the footer next to
# the build token, and used as the sitemap's <lastmod> and as dateModified in
# the structured data.
# ---------------------------------------------------------------------------
$assetVersionMode  = 'hash'
$assetVersionValue = '1.1'

function Get-Sha10([byte[]]$bytes) {
	$sha = [System.Security.Cryptography.SHA256]::Create()
	try   { $hash = $sha.ComputeHash($bytes) }
	finally { $sha.Dispose() }
	(($hash | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 10)
}
function Get-TextSha10([string]$text) { Get-Sha10 ([System.Text.Encoding]::UTF8.GetBytes($text)) }

# The version parameter ("v=6f2a91c0d4", "commit=36fe14c" or "version=1.1")
# for one asset file, or — given $text instead — for the build as a whole.
function Get-VersionParam([string]$absolutePath, [string]$text) {
	switch ($assetVersionMode) {
		'manual' { return 'version=' + $assetVersionValue }
		'commit' {
			$sha = $null
			try { $sha = (& git -C $root rev-parse --short HEAD 2>$null | Select-Object -First 1) } catch {}
			if (-not $sha) { throw "assetVersionMode is 'commit' but git could not resolve HEAD in $root" }
			return 'commit=' + $sha.Trim()
		}
		default {
			if (-not $absolutePath) { return 'v=' + (Get-TextSha10 $text) }
			if (-not (Test-Path $absolutePath)) { throw "cannot version a missing asset: $absolutePath" }
			return 'v=' + (Get-Sha10 ([System.IO.File]::ReadAllBytes($absolutePath)))
		}
	}
}

# Appends ?<version> to every href/src/content="[site URL]assets/..." in a page.
# The JSON-LD block is untouched: it never uses those attributes.
$assetParams  = @{}
$assetPattern = '(?<attr>(?:href|src|content)=")(?<base>' + [regex]::Escape($siteUrl) + ')?(?<path>assets/[^"?#]+?\.(?:css|js|svg|png|jpe?g|webp|gif|ico|woff2?))"'
function Add-AssetVersions([string]$html) {
	[regex]::Replace($html, $assetPattern, [System.Text.RegularExpressions.MatchEvaluator]{
		param($m)
		$path = $m.Groups['path'].Value
		if (-not $assetParams.ContainsKey($path)) {
			$assetParams[$path] = Get-VersionParam (Join-Path $root ($path -replace '/', '\'))
		}
		$m.Groups['attr'].Value + $m.Groups['base'].Value + $path + '?' + $assetParams[$path] + '"'
	})
}

# Extra sameAs entries for the alternate domains, appended inside the existing
# array in the layout. Guard against the primary being listed twice.
foreach ($d in $altDomains) {
	if ($d -eq $siteUrl) { throw "alt domain '$d' is the same as `$siteUrl - remove it from `$altDomains" }
	if ($d -notmatch '/$') { throw "alt domain '$d' must end with a trailing slash" }
}
$altDomainsJson = ''
foreach ($d in $altDomains) {
	$altDomainsJson += ",`r`n`t`t`t`t`t`t""$d"""
}

function Read-Utf8($path) { [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) }

# For HTML attribute values.
function Encode-Attr($s) {
	$s.Replace('&', '&amp;').Replace('"', '&quot;').Replace('<', '&lt;').Replace('>', '&gt;')
}

# For strings inside the JSON-LD block. HTML entities are NOT decoded inside a
# <script> element, so this must escape for JSON only and leave '&' alone.
function Encode-Json($s) {
	$s.Replace('\', '\\').Replace('"', '\"').Replace("`r", '').Replace("`n", ' ')
}

$layout = Read-Utf8 (Join-Path $tools '_layout.html')

$pages = @(
	# title   : kept under ~60 characters so Google shows it whole.
	# desc    : kept under ~160 characters, the usual snippet cut-off.
	# ogtitle : may run longer — social cards have more room than a search result.
	@{ out='index.html';      nav='home';    body='body-index.html'; crumb='Home'
		 title='CureComp Technology — IT, Networking & Cloud | Seremban'
		 ogtitle='CureComp Technology — IT, Networking, Cloud & PON Stick'
		 desc='Computers, managed IT, networking and Wi-Fi, cloud hosting and Malaysia''s first third-party GPON ONT. Seremban-based, with 24/7 live support.'
		 topbar='Seremban-based IT partner — supply, managed services, networking, cloud and fibre.' }

	@{ out='shop.html';       nav='shop';    body='body-shop.html'; crumb='Shop'
		 title='Computers, Parts & Repair in Seremban | CureComp'
		 ogtitle='Shop & Repair — Computers, Parts and Supplies'
		 desc='Desktops, laptops, components, peripherals and consumables in Seremban. Custom builds, upgrades, diagnostics, data recovery and on-site repair.'
		 topbar='Walk in, call, or send us a parts list — we''ll quote it.' }

	@{ out='managed-it.html'; nav='msp';     body='body-managed-it.html'; crumb='Managed IT'
		 title='Managed IT Services (MSP) Malaysia | CureComp'
		 ogtitle='Managed IT Services (MSP) with 24/7 Live Support'
		 desc='Managed IT for Malaysian business: device supply, Layer 2/3 networking, firewalls, site-to-site VPN, Wi-Fi and 24/7 live support.'
		 topbar='Managed IT with 24/7 live support — scoped to your requirement.' }

	@{ out='network.html';    nav='network'; body='body-network.html'; crumb='Networking'
		 title='Networking & Wi-Fi 6/7 Installation | CureComp'
		 ogtitle='Networking & Wi-Fi — Wi-Fi 6, Wi-Fi 7 and ISP-Grade Gear'
		 desc='Networking gear from home to ISP-grade, hardwired Wi-Fi 6 and Wi-Fi 7 roaming, fq_codel QoS, 10G fibre to the desk and free NOC monitoring.'
		 topbar='Networking and Wi-Fi — home, enterprise and ISP-grade.' }

	# Deep-dive guide. Deliberately NOT in the top navigation — it is reached from
	# network.html#wifi and from the footer. nav='network' so the parent menu item
	# still highlights while a visitor is reading it.
	@{ out='wifi-6-7.html';   nav='network'; body='body-wifi-6-7.html'; crumb='Wi-Fi 6 & 7 explained'
		 parentCrumb='Networking'; parentOut='network.html'
		 title='Wi-Fi 6 & Wi-Fi 7 Explained | CureComp Technology'
		 ogtitle='Wi-Fi 6 & Wi-Fi 7 Explained — Why to Stop Using Wi-Fi 5'
		 desc='How OFDMA, BSS Coloring, MU-MIMO, TWT and Wi-Fi 7 MLO actually work, with animated diagrams — and why Wi-Fi 5 and older hold a busy network back.'
		 topbar='A short lesson on 802.11ax and 802.11be — and why Wi-Fi 5 holds you back.' }

	# Special report on 802.11bn. Unlike the Wi-Fi 6/7 lesson it IS in the top
	# navigation, as a highlighted "New" item with its own nav key, and the page
	# carries a sticky chapter menu of its own (see body-wifi-8.html).
	@{ out='wifi-8.html';     nav='wifi8';   body='body-wifi-8.html'; crumb='Wi-Fi 8 explained'
		 parentCrumb='Networking'; parentOut='network.html'
		 title='Wi-Fi 8 (802.11bn) Explained | CureComp Technology'
		 ogtitle='Wi-Fi 8 Explained — Ultra High Reliability, Wi-Fi That Behaves Like a Cable'
		 desc='How Wi-Fi 8 (IEEE 802.11bn) trades peak speed for reliability: ELR, DRU, NPCA, seamless roaming and multi-AP coordination, animated, plus the road to 2028.'
		 topbar='Special report: Wi-Fi 8 (IEEE 802.11bn) — wireless that behaves like a cable.' }

	@{ out='cloud.html';      nav='cloud';   body='body-cloud.html'; crumb='Cloud'
		 title='Dedicated Servers, Colocation & Cloud | CureComp'
		 ogtitle='Cloud, Colocation & Dedicated Servers on AS154516'
		 desc='Dedicated servers, colocation and VM/LXC on AS154516. 1Gbps burstable to 10Gbps, IPv6 up to a /48, and dedicated 10Gbps built to order.'
		 topbar='Data centre operator · Digital infrastructure · Telecom services.' }

	@{ out='pon-stick.html';  nav='pon';     body='body-pon-stick.html'; crumb='PON Stick'
		 title='PON Stick — Malaysia''s First Third-Party ONT | CureComp'
		 ogtitle='PON Stick — Malaysia''s First Third-Party GPON ONT'
		 desc='Official Anime4000 GPON Stick and NIJIKA SDK supplier. Third-party ONT for TM Unifi, Maxis, TIME and PERFECT, with Grafana monitoring.'
		 topbar='Official Anime4000 GPON Stick and NIJIKA Firmware SDK supplier.' }

	@{ out='about.html';      nav='about';   body='body-about.html'; crumb='About'
		 title='About Us & Our Clients | CureComp Technology'
		 ogtitle='About CureComp Technology & Our Clients'
		 desc='CureComp Technology (Reg. 201603089199) — Seremban computer supplier, MSP, networking specialist and cloud operator. See who we have served.'
		 topbar='CureComp Technology — Reg. 201603089199 (NS0161352-H)' }

	@{ out='contact.html';    nav='contact'; body='body-contact.html'; crumb='Contact'
		 title='Contact & Request a Quote | CureComp Technology'
		 ogtitle='Contact CureComp Technology — Request a Quote'
		 desc='Contact CureComp Technology in Seremban. Call +6017-877 4376, WhatsApp, or send an enquiry for computers, managed IT, networking, cloud or PON Stick.'
		 topbar='Quotes for managed IT and cloud are tailored to your requirement.' }
)

$today = (Get-Date).ToString('yyyy-MM-dd')

# ---------- per-page "last updated" record ----------
# tools/versions.json maps each page to a hash of its own content (body
# fragment plus title, descriptions and top-bar line — not the shared layout,
# so a navbar tweak doesn't re-date every page) and the date that hash last
# changed. A page seen for the first time takes the date of the last commit
# that touched its body file, or today if that file has uncommitted edits.
$versionsPath = Join-Path $tools 'versions.json'
$versions = @{}
if (Test-Path $versionsPath) {
	$json = (Read-Utf8 $versionsPath) | ConvertFrom-Json
	foreach ($prop in $json.PSObject.Properties) {
		$versions[$prop.Name] = @{ hash = $prop.Value.hash; updated = $prop.Value.updated }
	}
}

function Get-SeedDate($bodyPath) {
	try {
		$dirty = & git -C $root status --porcelain -- $bodyPath 2>$null
		if (-not $dirty) {
			$date = & git -C $root log -1 --format=%cs -- $bodyPath 2>$null | Select-Object -First 1
			if ($date) { return $date.Trim() }
		}
	} catch {}
	return $today
}

# ---------- pass 1: assemble every page ----------
# Pages are assembled first and stamped second, because the build token is a
# hash over all of them.
$fingerprint = New-Object System.Text.StringBuilder
foreach ($p in $pages) {
	$canonical = if ($p.out -eq 'index.html') { $siteUrl } else { $siteUrl + $p.out }
	$bodyPath  = Join-Path $tools $p.body
	$body      = Read-Utf8 $bodyPath

	$contentHash = Get-TextSha10 ($body + "`n" + $p.title + "`n" + $p.ogtitle + "`n" + $p.desc + "`n" + $p.topbar + "`n" + $p.crumb)
	$known = $versions[$p.out]
	if ($known -and $known.hash -eq $contentHash) { $updated = $known.updated }
	elseif ($known) { $updated = $today }
	else { $updated = Get-SeedDate $bodyPath }
	$p.contentHash = $contentHash
	$p.updated     = $updated

	# Home is the root of the trail, so it gets no breadcrumb of its own.
	# A page may declare a parent (parentCrumb/parentOut) to get a third level.
	$breadcrumb = ''
	if ($p.out -ne 'index.html') {
		$items = @("`t`t`t`t`t{ ""@type"": ""ListItem"", ""position"": 1, ""name"": ""Home"", ""item"": ""$siteUrl"" }")
		$pos = 2
		if ($p.parentCrumb) {
			$items += "`t`t`t`t`t{ ""@type"": ""ListItem"", ""position"": $pos, ""name"": ""$(Encode-Json $p.parentCrumb)"", ""item"": ""$siteUrl$($p.parentOut)"" }"
			$pos++
		}
		$items += "`t`t`t`t`t{ ""@type"": ""ListItem"", ""position"": $pos, ""name"": ""$(Encode-Json $p.crumb)"", ""item"": ""$canonical"" }"
		$breadcrumb = ",`r`n`t`t`t{`r`n`t`t`t`t""@type"": ""BreadcrumbList"",`r`n`t`t`t`t""@id"": ""$canonical#breadcrumb"",`r`n`t`t`t`t""itemListElement"": [`r`n" +
									($items -join ",`r`n") + "`r`n`t`t`t`t]`r`n`t`t`t}"
	}

	$html = $layout
	$html = $html.Replace('{{TITLE}}',        (Encode-Attr $p.title))
	$html = $html.Replace('{{OGTITLE_JSON}}', (Encode-Json $p.ogtitle))
	$html = $html.Replace('{{OGTITLE}}',      (Encode-Attr $p.ogtitle))
	$html = $html.Replace('{{DESC_JSON}}',    (Encode-Json $p.desc))
	$html = $html.Replace('{{DESC}}',         (Encode-Attr $p.desc))
	$html = $html.Replace('{{CANONICAL}}',    $canonical)
	$html = $html.Replace('{{BASE}}',         $siteUrl)
	$html = $html.Replace('{{BREADCRUMB}}',   $breadcrumb)
	$html = $html.Replace('{{TOPBAR}}',       $p.topbar)
	$html = $html.Replace('{{ALT_DOMAINS}}',  $altDomainsJson)
	$html = $html.Replace('{{UPDATED}}',      $updated)
	$html = $html.Replace('{{UPDATED_HUMAN}}', ([datetime]::ParseExact($updated, 'yyyy-MM-dd', $null)).ToString('d MMM yyyy', [Globalization.CultureInfo]::InvariantCulture))
	$html = $html.Replace('{{BODY}}',         $body)

	# Mark the current page in the navbar.
	$needle = 'class="nav-link" data-nav="' + $p.nav + '"'
	$marked = 'class="nav-link active" aria-current="page" data-nav="' + $p.nav + '"'
	if ($html -notmatch [regex]::Escape($needle)) { throw "nav key '$($p.nav)' not found in layout" }
	$html = $html.Replace($needle, $marked)

	# Asset tokens go in now, so the build token below covers asset changes too.
	$html = Add-AssetVersions $html
	$p.html = $html
	[void]$fingerprint.Append($p.out).Append("`n").Append($html).Append("`n")
}

# ---------- pass 2: stamp page links and write ----------
$buildParam = Get-VersionParam $null $fingerprint.ToString()
$buildId    = $buildParam.Substring($buildParam.IndexOf('=') + 1)

# Relative links to any page in the table, keeping an existing query string and
# fragment: contact.html?topic=wifi#enquiry -> contact.html?topic=wifi&v=...#enquiry.
# Absolute URLs (canonical, og:url) never match, so they stay clean.
$pageNames   = ($pages | ForEach-Object { [regex]::Escape($_.out) }) -join '|'
$linkPattern = 'href="(?<page>' + $pageNames + ')(?<query>\?[^"#]*)?(?<frag>#[^"]*)?"'
$linkStamper = [System.Text.RegularExpressions.MatchEvaluator]{
	param($m)
	$q = if ($m.Groups['query'].Success) { $m.Groups['query'].Value + '&' } else { '?' }
	'href="' + $m.Groups['page'].Value + $q + $buildParam + $m.Groups['frag'].Value + '"'
}

foreach ($p in $pages) {
	$html = $p.html.Replace('{{BUILD}}', $buildId)
	$html = [regex]::Replace($html, $linkPattern, $linkStamper)

	if ($html -match '{{') { throw "unreplaced placeholder left in $($p.out)" }

	[System.IO.File]::WriteAllText((Join-Path $root $p.out), $html, $utf8)
	Write-Output ("built {0,-16} {1,6:N1} KB   updated {2}" -f $p.out, ((Get-Item (Join-Path $root $p.out)).Length / 1KB), $p.updated)
}

# ---------- tools/versions.json ----------
# Rewritten only when a page's content actually changed, so a no-op rebuild
# leaves the working tree clean.
$entries = foreach ($p in $pages) {
	"`t""$($p.out)"": { ""hash"": ""$($p.contentHash)"", ""updated"": ""$($p.updated)"" }"
}
$versionsJson = "{`r`n" + ($entries -join ",`r`n") + "`r`n}`r`n"
$previous = if (Test-Path $versionsPath) { Read-Utf8 $versionsPath } else { '' }
if ($versionsJson -ne $previous) {
	[System.IO.File]::WriteAllText($versionsPath, $versionsJson, $utf8)
	Write-Output 'updated tools/versions.json'
}

# ---------- sitemap.xml ----------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
[void]$sb.AppendLine('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">')
foreach ($p in $pages) {
	$loc      = if ($p.out -eq 'index.html') { $siteUrl } else { $siteUrl + $p.out }
	$priority = if ($p.out -eq 'index.html') { '1.0' } else { '0.8' }
	[void]$sb.AppendLine("`t<url>")
	[void]$sb.AppendLine("`t`t<loc>$loc</loc>")
	[void]$sb.AppendLine("`t`t<lastmod>$($p.updated)</lastmod>")
	[void]$sb.AppendLine("`t`t<changefreq>monthly</changefreq>")
	[void]$sb.AppendLine("`t`t<priority>$priority</priority>")
	[void]$sb.AppendLine("`t</url>")
}
[void]$sb.AppendLine('</urlset>')
[System.IO.File]::WriteAllText((Join-Path $root 'sitemap.xml'), $sb.ToString(), $utf8)
Write-Output 'built sitemap.xml'

# ---------- robots.txt ----------
$robots = @"
User-agent: *
Allow: /
Disallow: /tools/

Sitemap: $($siteUrl)sitemap.xml
"@
[System.IO.File]::WriteAllText((Join-Path $root 'robots.txt'), $robots, $utf8)
Write-Output 'built robots.txt'

Write-Output "`nDone. $($pages.Count) pages written to $root"
Write-Output "Canonical domain : $siteUrl"
foreach ($d in $altDomains) {
	Write-Output "Alternate domain : $d  (canonicalised to the primary)"
}
Write-Output "Build token      : $buildParam  (on every page link, and in each footer)"
Write-Output "theme.css        : ?$($assetParams['assets/css/theme.css'])"
Write-Output "main.js          : ?$($assetParams['assets/js/main.js'])"
Write-Output "Assets stamped   : $($assetParams.Count) files"

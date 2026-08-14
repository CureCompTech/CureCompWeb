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
# Cache busting for theme.css and main.js.
#
# Cloudflare (and every browser) keys its cache on the full URL including the
# query string, so changing the token forces a fresh fetch after an upload.
#
#   'hash'   default. A short SHA-256 of that file's own contents, e.g.
#            ?v=6f2a91c0d4. The URL changes if and only if the file actually
#            changed, and each asset is versioned independently — editing the
#            CSS does not throw away the cached JS. Nothing to remember.
#   'commit' the short git commit of HEAD, e.g. ?commit=36fe14c. Note this is
#            HEAD at BUILD time, so it names the commit before the one that
#            carries the rebuilt pages.
#   'manual' the fixed string in $assetVersionValue, e.g. ?version=1.1. You
#            must remember to bump it, or visitors keep the stale file.
# ---------------------------------------------------------------------------
$assetVersionMode  = 'hash'
$assetVersionValue = '1.1'

function Get-AssetQuery($absolutePath) {
	switch ($assetVersionMode) {
		'manual' { return '?version=' + $assetVersionValue }
		'commit' {
			$sha = $null
			try { $sha = (& git -C $root rev-parse --short HEAD 2>$null | Select-Object -First 1) } catch {}
			if (-not $sha) { throw "assetVersionMode is 'commit' but git could not resolve HEAD in $root" }
			return '?commit=' + $sha.Trim()
		}
		default {
			if (-not (Test-Path $absolutePath)) { throw "cannot version a missing asset: $absolutePath" }
			$sha = [System.Security.Cryptography.SHA256]::Create()
			try   { $bytes = $sha.ComputeHash([System.IO.File]::ReadAllBytes($absolutePath)) }
			finally { $sha.Dispose() }
			return '?v=' + ((($bytes | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 10))
		}
	}
}

$cssQuery = Get-AssetQuery (Join-Path $root 'assets\css\theme.css')
$jsQuery  = Get-AssetQuery (Join-Path $root 'assets\js\main.js')

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

foreach ($p in $pages) {
	$canonical = if ($p.out -eq 'index.html') { $siteUrl } else { $siteUrl + $p.out }

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
	$html = $html.Replace('{{CSS_Q}}',        $cssQuery)
	$html = $html.Replace('{{JS_Q}}',         $jsQuery)
	$html = $html.Replace('{{ALT_DOMAINS}}',  $altDomainsJson)
	$html = $html.Replace('{{BODY}}',         (Read-Utf8 (Join-Path $tools $p.body)))

	# Mark the current page in the navbar.
	$needle = 'class="nav-link" data-nav="' + $p.nav + '"'
	$marked = 'class="nav-link active" aria-current="page" data-nav="' + $p.nav + '"'
	if ($html -notmatch [regex]::Escape($needle)) { throw "nav key '$($p.nav)' not found in layout" }
	$html = $html.Replace($needle, $marked)

	if ($html -match '{{') { throw "unreplaced placeholder left in $($p.out)" }

	[System.IO.File]::WriteAllText((Join-Path $root $p.out), $html, $utf8)
	Write-Output ("built {0,-16} {1,6:N1} KB" -f $p.out, ((Get-Item (Join-Path $root $p.out)).Length / 1KB))
}

# ---------- sitemap.xml ----------
$today = (Get-Date).ToString('yyyy-MM-dd')
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
[void]$sb.AppendLine('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">')
foreach ($p in $pages) {
	$loc      = if ($p.out -eq 'index.html') { $siteUrl } else { $siteUrl + $p.out }
	$priority = if ($p.out -eq 'index.html') { '1.0' } else { '0.8' }
	[void]$sb.AppendLine("`t<url>")
	[void]$sb.AppendLine("`t`t<loc>$loc</loc>")
	[void]$sb.AppendLine("`t`t<lastmod>$today</lastmod>")
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
Write-Output "theme.css        : $cssQuery"
Write-Output "main.js          : $jsQuery"

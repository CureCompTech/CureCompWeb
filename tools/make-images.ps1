<#
	Generates the raster images the HTML references but cannot produce itself:

		assets/img/og-cover.png        1200x630  social preview card
		assets/img/apple-touch-icon.png 180x180  iOS home-screen icon

	Facebook, Twitter/X, Discord, LinkedIn and WhatsApp will not render an SVG
	as a preview image, so these have to be PNG.

	Run once, or again after changing the branding:
		powershell -ExecutionPolicy Bypass -File tools\make-images.ps1
#>

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$img  = Join-Path $root 'assets\img'

$bg     = [System.Drawing.Color]::FromArgb(255, 13, 14, 16)
$red    = [System.Drawing.Color]::FromArgb(255, 237, 34, 36)
$white  = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
$muted  = [System.Drawing.Color]::FromArgb(255, 154, 164, 176)

function New-Canvas([int]$w, [int]$h) {
	$bmp = New-Object System.Drawing.Bitmap $w, $h
	$g   = [System.Drawing.Graphics]::FromImage($bmp)
	$g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
	$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
	$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
	$g.Clear($bg)
	return @{ Bitmap = $bmp; Graphics = $g }
}

# Soft radial wash, matching the red glow behind the site's hero sections.
function Add-Glow($g, [int]$cx, [int]$cy, [int]$radius, [int]$alpha) {
	$path = New-Object System.Drawing.Drawing2D.GraphicsPath
	$path.AddEllipse(($cx - $radius), ($cy - $radius), ($radius * 2), ($radius * 2))
	$brush = New-Object System.Drawing.Drawing2D.PathGradientBrush $path
	$brush.CenterColor    = [System.Drawing.Color]::FromArgb($alpha, $red)
	$brush.SurroundColors = @([System.Drawing.Color]::FromArgb(0, $red))
	$g.FillPath($brush, $path)
	$brush.Dispose(); $path.Dispose()
}

# Simplified brand mark: open ring with the red angled accent at its top right.
function Add-Mark($g, [single]$x, [single]$y, [single]$size, [single]$stroke) {
	$pen = New-Object System.Drawing.Pen $white, $stroke
	$pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
	$pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
	$inset = $stroke / 2
	$g.DrawArc($pen, ($x + $inset), ($y + $inset), ($size - $stroke), ($size - $stroke), 305, 290)
	$pen.Dispose()

	$brush = New-Object System.Drawing.SolidBrush $red
	$pts = @(
		(New-Object System.Drawing.PointF (($x + $size * 0.62), ($y + $size * 0.16))),
		(New-Object System.Drawing.PointF (($x + $size * 1.00), ($y + $size * 0.16))),
		(New-Object System.Drawing.PointF (($x + $size * 0.86), ($y + $size * 0.46))),
		(New-Object System.Drawing.PointF (($x + $size * 0.86), ($y + $size * 0.02)))
	)
	$g.FillPolygon($brush, $pts)
	$brush.Dispose()
}

# ---------- 1200x630 social card ----------
$c = New-Canvas 1200 630
$g = $c.Graphics

Add-Glow $g 120  40  620 105
Add-Glow $g 1120 620 560 70

# Red rule down the left edge.
$edge = New-Object System.Drawing.SolidBrush $red
$g.FillRectangle($edge, 0, 0, 10, 630)
$edge.Dispose()

Add-Mark $g 84 78 104 15

$fTitle = New-Object System.Drawing.Font 'Segoe UI', 74, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
$fSub   = New-Object System.Drawing.Font 'Segoe UI', 33, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
$fFoot  = New-Object System.Drawing.Font 'Segoe UI', 25, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)

$bWhite = New-Object System.Drawing.SolidBrush $white
$bMuted = New-Object System.Drawing.SolidBrush $muted
$bRed   = New-Object System.Drawing.SolidBrush $red

$g.DrawString('CureComp Technology', $fTitle, $bWhite, 84, 232)
$g.DrawString('Computers  ·  Managed IT  ·  Networking  ·  Cloud  ·  PON Stick', $fSub, $bMuted, 88, 336)

$g.FillRectangle($bRed, 88, 412, 96, 5)
$g.DrawString('Seremban, Negeri Sembilan  ·  +6017-877 4376', $fFoot, $bMuted, 88, 448)
$g.DrawString('24/7 live support  ·  Reg. 201603089199 (NS0161352-H)', $fFoot, $bMuted, 88, 488)

$c.Bitmap.Save((Join-Path $img 'og-cover.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$fTitle.Dispose(); $fSub.Dispose(); $fFoot.Dispose()
$bWhite.Dispose(); $bMuted.Dispose(); $bRed.Dispose()
$g.Dispose(); $c.Bitmap.Dispose()
Write-Output 'wrote assets/img/og-cover.png (1200x630)'

# ---------- 180x180 apple touch icon ----------
$c2 = New-Canvas 180 180
$g2 = $c2.Graphics
Add-Glow $g2 40 20 150 90
Add-Mark $g2 30 34 120 17
$c2.Bitmap.Save((Join-Path $img 'apple-touch-icon.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$g2.Dispose(); $c2.Bitmap.Dispose()
Write-Output 'wrote assets/img/apple-touch-icon.png (180x180)'

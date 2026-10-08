param([switch]$recompress)
# Builds assets/sm (800px long edge) for on-page photos. -recompress also re-saves the full-size
# lightbox photos at quality 82; run that once only, since each JPEG re-save loses a little detail.
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
$assets = Join-Path $root "assets"
$sm = Join-Path $assets "sm"
New-Item -ItemType Directory -Force $sm | Out-Null
$enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" }

function Save-Jpeg($bmp, [string]$path, [long]$q) {
  $ep = New-Object System.Drawing.Imaging.EncoderParameters 1
  $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), $q
  $tmp = $path + ".tmp"
  $bmp.Save($tmp, $enc, $ep)
  Move-Item -Force $tmp $path
}

function Resize($src, [int]$long) {
  $scale = [Math]::Min(1.0, $long / [double][Math]::Max($src.Width, $src.Height))
  $w = [int][Math]::Round($src.Width * $scale); $h = [int][Math]::Round($src.Height * $scale)
  $out = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $g = [System.Drawing.Graphics]::FromImage($out)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.DrawImage($src, 0, 0, $w, $h)
  $g.Dispose()
  return $out
}

$photos = Get-ChildItem $assets -File -Filter *.jpg | Where-Object { $_.Name -match "^(extra-\d+|vibe)\.jpg$" }
foreach ($f in $photos) {
  $src = New-Object System.Drawing.Bitmap $f.FullName
  $small = Resize $src 800
  Save-Jpeg $small (Join-Path $sm $f.Name) 72
  $small.Dispose()
  if ($recompress) {
    $copy = Resize $src 1600
    $src.Dispose()
    Save-Jpeg $copy $f.FullName 82
    $copy.Dispose()
  } else {
    $src.Dispose()
  }
}

$logoPath = Join-Path $assets "logo.jpg"
$logo = New-Object System.Drawing.Bitmap $logoPath
if ($logo.Width -gt 720) {
  $small = Resize $logo 720
  $logo.Dispose()
  Save-Jpeg $small $logoPath 88
  $small.Dispose()
} else {
  $logo.Dispose()
}
Write-Output "sized $($photos.Count) photos"

param([switch]$preview, [string]$only = "")
Add-Type -AssemblyName System.Drawing
$cs = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class PlateMask1 {
  static byte[] Read(Bitmap bmp, out int stride) {
    var d = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
    stride = d.Stride;
    var buf = new byte[stride * bmp.Height];
    Marshal.Copy(d.Scan0, buf, 0, buf.Length);
    bmp.UnlockBits(d);
    return buf;
  }
  static void Write(Bitmap bmp, byte[] buf) {
    var d = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.WriteOnly, PixelFormat.Format24bppRgb);
    Marshal.Copy(buf, 0, d.Scan0, buf.Length);
    bmp.UnlockBits(d);
  }

  // Returns quad corners TL, TR, BR, BL as x0,y0,...,x3,y3 in pixels.
  public static double[] Detect(Bitmap bmp, double fx, double fy, double fw, double fh) {
    int W = bmp.Width, H = bmp.Height, stride;
    var px = Read(bmp, out stride);
    int bx = (int)(W * fx), by = (int)(H * fy), bw = (int)(W * fw), bh = (int)(H * fh);
    int sx0 = Math.Max(0, bx - bw / 3), sy0 = Math.Max(0, by - bh / 2);
    int sx1 = Math.Min(W, bx + bw + bw / 3), sy1 = Math.Min(H, by + bh + bh / 2);
    int sw = sx1 - sx0, sh = sy1 - sy0;
    var s = new int[sw * sh];
    var hist = new int[256];
    for (int y = 0; y < sh; y++)
      for (int x = 0; x < sw; x++) {
        int i = (sy0 + y) * stride + (sx0 + x) * 3;
        int v = Math.Min(px[i + 1], px[i + 2]);
        s[y * sw + x] = v; hist[v]++;
      }
    int total = sw * sh; double sum = 0;
    for (int k = 0; k < 256; k++) sum += k * hist[k];
    double sumB = 0, best = -1; int wB = 0, t = 128;
    for (int k = 0; k < 256; k++) {
      wB += hist[k]; if (wB == 0) continue;
      int wF = total - wB; if (wF == 0) break;
      sumB += k * hist[k];
      double mB = sumB / wB, mF = (sum - sumB) / wF;
      double between = (double)wB * wF * (mB - mF) * (mB - mF);
      if (between > best) { best = between; t = k; }
    }
    var lab = new int[total];
    double ccx = bx + bw / 2.0 - sx0, ccy = by + bh / 2.0 - sy0;
    double bestScore = -1; int bestLab = 0; int next = 1;
    var q = new Queue<int>();
    for (int p0 = 0; p0 < total; p0++) {
      if (lab[p0] != 0 || s[p0] <= t) continue;
      int id = next++; lab[p0] = id; q.Enqueue(p0);
      int area = 0, mnx = sw, mny = sh, mxx = 0, mxy = 0; double mx = 0, my = 0;
      while (q.Count > 0) {
        int p = q.Dequeue(); int x = p % sw, y = p / sw;
        area++; mx += x; my += y;
        if (x < mnx) mnx = x; if (x > mxx) mxx = x; if (y < mny) mny = y; if (y > mxy) mxy = y;
        if (x > 0 && lab[p - 1] == 0 && s[p - 1] > t) { lab[p - 1] = id; q.Enqueue(p - 1); }
        if (x < sw - 1 && lab[p + 1] == 0 && s[p + 1] > t) { lab[p + 1] = id; q.Enqueue(p + 1); }
        if (y > 0 && lab[p - sw] == 0 && s[p - sw] > t) { lab[p - sw] = id; q.Enqueue(p - sw); }
        if (y < sh - 1 && lab[p + sw] == 0 && s[p + sw] > t) { lab[p + sw] = id; q.Enqueue(p + sw); }
      }
      int cw = mxx - mnx + 1, ch = mxy - mny + 1;
      if (area < 40 || ch < 4) continue;
      double ar = (double)cw / ch;
      if (ar < 0.3 || ar > 7.5) continue;
      int rx0 = bx - sx0, ry0 = by - sy0, rx1 = rx0 + bw, ry1 = ry0 + bh;
      int ix = Math.Max(0, Math.Min(mxx + 1, rx1) - Math.Max(mnx, rx0));
      int iy = Math.Max(0, Math.Min(mxy + 1, ry1) - Math.Max(mny, ry0));
      double inter = (double)ix * iy;
      double union = (double)cw * ch + (double)bw * bh - inter;
      double score = inter / union;
      if (score > bestScore) { bestScore = score; bestLab = id; }
    }
    if (bestLab == 0) return null;
    double[] best4 = new double[8];
    double tl = double.MaxValue, br = double.MinValue, tr = double.MinValue, bl = double.MinValue;
    for (int p = 0; p < total; p++) {
      if (lab[p] != bestLab) continue;
      int x = p % sw, y = p / sw;
      double a = x + y, b = x - y;
      if (a < tl) { tl = a; best4[0] = x; best4[1] = y; }
      if (b > tr) { tr = b; best4[2] = x + 1; best4[3] = y; }
      if (a > br) { br = a; best4[4] = x + 1; best4[5] = y + 1; }
      if (-b > bl) { bl = -b; best4[6] = x; best4[7] = y + 1; }
    }
    for (int k = 0; k < 8; k += 2) { best4[k] += sx0; best4[k + 1] += sy0; }
    return best4;
  }

  static double Inside(double[] qd, double x, double y) {
    double d = double.MaxValue;
    double area = 0;
    for (int k = 0; k < 4; k++) {
      int j = (k + 1) % 4;
      area += qd[k * 2] * qd[j * 2 + 1] - qd[j * 2] * qd[k * 2 + 1];
    }
    double sgn = area >= 0 ? 1 : -1;
    for (int k = 0; k < 4; k++) {
      int j = (k + 1) % 4;
      double ax = qd[k * 2], ay = qd[k * 2 + 1], ex = qd[j * 2] - ax, ey = qd[j * 2 + 1] - ay;
      double len = Math.Sqrt(ex * ex + ey * ey); if (len < 1e-6) continue;
      double dist = sgn * (ex * (y - ay) - ey * (x - ax)) / len;
      if (dist < d) d = dist;
    }
    return d;
  }

  public static void Grow(double[] qd, double by) {
    double cx = 0, cy = 0;
    for (int k = 0; k < 4; k++) { cx += qd[k * 2] / 4; cy += qd[k * 2 + 1] / 4; }
    for (int k = 0; k < 4; k++) {
      double dx = qd[k * 2] - cx, dy = qd[k * 2 + 1] - cy;
      double len = Math.Sqrt(dx * dx + dy * dy); if (len < 1e-6) continue;
      qd[k * 2] += dx / len * by * 1.41; qd[k * 2 + 1] += dy / len * by * 1.41;
    }
  }

  public static void Apply(Bitmap bmp, double[] qd) {
    int W = bmp.Width, H = bmp.Height, stride;
    var px = Read(bmp, out stride);
    double mnx = W, mny = H, mxx = 0, mxy = 0;
    for (int k = 0; k < 4; k++) {
      mnx = Math.Min(mnx, qd[k * 2]); mxx = Math.Max(mxx, qd[k * 2]);
      mny = Math.Min(mny, qd[k * 2 + 1]); mxy = Math.Max(mxy, qd[k * 2 + 1]);
    }
    int x0 = Math.Max(0, (int)mnx - 2), y0 = Math.Max(0, (int)mny - 2);
    int x1 = Math.Min(W, (int)Math.Ceiling(mxx) + 2), y1 = Math.Min(H, (int)Math.Ceiling(mxy) + 2);
    int w = x1 - x0, h = y1 - y0;
    if (w < 4 || h < 4) return;
    var a = new double[w * h];
    var c = new double[w * h * 3];
    var lums = new List<int>();
    for (int y = 0; y < h; y++)
      for (int x = 0; x < w; x++) {
        double d = Inside(qd, x0 + x + 0.5, y0 + y + 0.5);
        double al = Math.Max(0, Math.Min(1, d + 0.5));
        a[y * w + x] = al;
        int i = (y0 + y) * stride + (x0 + x) * 3;
        for (int ch = 0; ch < 3; ch++) c[(y * w + x) * 3 + ch] = px[i + ch] * al;
        if (al >= 1) lums.Add((px[i] << 16) | (px[i + 1] << 8) | px[i + 2]);
      }
    double plateH = Math.Min(mxx - mnx, mxy - mny);
    int r = Math.Max(3, (int)(plateH * 0.45));
    var wa = (double[])a.Clone();
    for (int pass = 0; pass < 3; pass++) { Box(c, w, h, 3, r); Box(wa, w, h, 1, r); }
    lums.Sort((p, q2) => (((p >> 8) & 255) + (p & 255)).CompareTo(((q2 >> 8) & 255) + (q2 & 255)));
    double tb = 200, tg = 200, tr = 200;
    if (lums.Count > 10) {
      int from = (int)(lums.Count * 0.55), to = (int)(lums.Count * 0.9); tb = tg = tr = 0;
      for (int k = from; k < to; k++) { tb += (lums[k] >> 16) & 255; tg += (lums[k] >> 8) & 255; tr += lums[k] & 255; }
      int n = to - from; tb /= n; tg /= n; tr /= n;
    }
    var rnd = new Random(W * 7919 + H);
    for (int y = 0; y < h; y++)
      for (int x = 0; x < w; x++) {
        double al = a[y * w + x]; if (al <= 0) continue;
        double wt = Math.Max(1e-6, wa[y * w + x]);
        int i = (y0 + y) * stride + (x0 + x) * 3;
        double grain = (rnd.NextDouble() - 0.5) * 3;
        double[] tone = { tb, tg, tr };
        for (int ch = 0; ch < 3; ch++) {
          double blurred = c[(y * w + x) * 3 + ch] / wt;
          double v = blurred * 0.55 + tone[ch] * 0.45 + grain;
          double o = px[i + ch] * (1 - al) + v * al;
          px[i + ch] = (byte)Math.Max(0, Math.Min(255, Math.Round(o)));
        }
      }
    Write(bmp, px);
  }

  static void Box(double[] v, int w, int h, int n, int r) {
    var tmp = new double[v.Length];
    for (int y = 0; y < h; y++)
      for (int ch = 0; ch < n; ch++) {
        double acc = 0; int cnt = 0;
        for (int x = -r; x < w + r; x++) {
          int add = x + r, rem = x - r - 1;
          if (add >= 0 && add < w) { acc += v[(y * w + add) * n + ch]; cnt++; }
          if (rem >= 0 && rem < w) { acc -= v[(y * w + rem) * n + ch]; cnt--; }
          if (x >= 0 && x < w) tmp[(y * w + x) * n + ch] = acc / Math.Max(1, cnt);
        }
      }
    for (int x = 0; x < w; x++)
      for (int ch = 0; ch < n; ch++) {
        double acc = 0; int cnt = 0;
        for (int y = -r; y < h + r; y++) {
          int add = y + r, rem = y - r - 1;
          if (add >= 0 && add < h) { acc += tmp[(add * w + x) * n + ch]; cnt++; }
          if (rem >= 0 && rem < h) { acc -= tmp[(rem * w + x) * n + ch]; cnt--; }
          if (y >= 0 && y < h) v[(y * w + x) * n + ch] = acc / Math.Max(1, cnt);
        }
      }
  }
}
'@
Add-Type -TypeDefinition $cs -ReferencedAssemblies System.Drawing

$enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" }
$ep = New-Object System.Drawing.Imaging.EncoderParameters 1
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), ([long]82)

# r: rough search box (fraction x, y, w, h). q: optional exact quad in fractions TL,TR,BR,BL overriding detection.
# Photos 3, 4, 8, 9, 13, 27, 37 and 51 show no readable plate (dealer stickers or out of frame).
$jobs = @(
  @{ n = "extra-14.jpg"; r = @(,@(0.722, 0.643, 0.037, 0.085)) },
  @{ n = "extra-21.jpg"; r = @(,@(0.70, 0.465, 0.14, 0.065)) },
  @{ n = "extra-25.jpg"; r = @(,@(0.273, 0.478, 0.07, 0.04)) },
  @{ n = "extra-26.jpg"; r = @(,@(0.42, 0.798, 0.32, 0.07)) },
  @{ n = "extra-29.jpg"; r = @(,@(0.68, 0.645, 0.18, 0.08)) },
  @{ n = "extra-30.jpg"; r = @(,@(0.51, 0.495, 0.15, 0.075)) },
  @{ n = "extra-36.jpg"; r = @(,@(0.53, 0.495, 0.15, 0.065)) },
  @{ n = "extra-38.jpg"; r = @(,@(0.38, 0.64, 0.24, 0.09)) },
  @{ n = "extra-41.jpg"; r = @(,@(0.252, 0.53, 0.04, 0.045)) },
  @{ n = "extra-42.jpg"; r = @(,@(0.115, 0.632, 0.04, 0.04)) },
  @{ n = "extra-44.jpg"; r = @(,@(0.172, 0.672, 0.078, 0.07)) },
  @{ n = "extra-46.jpg"; r = @(,@(0.15, 0.472, 0.037, 0.045)) },
  @{ n = "extra-48.jpg"; r = @(,@(0.228, 0.545, 0.052, 0.045)) },
  @{ n = "extra-52.jpg"; r = @(,@(0.822, 0.71, 0.045, 0.05)) },
  @{ n = "extra-54.jpg"; r = @(,@(0.47, 0.785, 0.26, 0.08)) },
  @{ n = "extra-56.jpg"; r = @(,@(0.235, 0.635, 0.067, 0.055)) }
)
# Plates that touch a white bumper, sit in shadow or hide behind a bar are traced by hand.
$overrides = @{
  "extra-26.jpg#0" = @(0.484, 0.798, 0.641, 0.798, 0.641, 0.839, 0.484, 0.839);
  "extra-29.jpg#0" = @(0.7025, 0.6755, 0.7890, 0.6275, 0.7890, 0.6705, 0.7050, 0.7125);
  "extra-42.jpg#0" = @(0.117, 0.637, 0.152, 0.641, 0.152, 0.672, 0.117, 0.667);
  "extra-52.jpg#0" = @(0.8357, 0.7353, 0.8611, 0.7108, 0.8554, 0.7499, 0.8308, 0.7669);
  "extra-56.jpg#0" = @(0.2503, 0.6343, 0.3005, 0.6725, 0.2945, 0.6950, 0.2522, 0.6650)
}

function Load24([string]$path) {
  $src = New-Object System.Drawing.Bitmap $path
  $bmp = New-Object System.Drawing.Bitmap $src.Width, $src.Height, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.DrawImage($src, 0, 0, $src.Width, $src.Height)
  $g.Dispose(); $src.Dispose()
  return $bmp
}

function Get-Quads($bmp, [string]$name, $rects) {
  $out = @()
  $idx = 0
  foreach ($box in $rects) {
    $key = "$name#$idx"
    if ($overrides.ContainsKey($key)) {
      $f = $overrides[$key]
      $qd = New-Object double[] 8
      for ($k = 0; $k -lt 8; $k += 2) { $qd[$k] = $f[$k] * $bmp.Width; $qd[$k + 1] = $f[$k + 1] * $bmp.Height }
    } else {
      $qd = [PlateMask1]::Detect($bmp, [double]$box[0], [double]$box[1], [double]$box[2], [double]$box[3])
    }
    if ($qd) {
      $hgt = [Math]::Abs($qd[7] - $qd[1])
      [PlateMask1]::Grow($qd, [Math]::Max(1.5, $hgt * 0.04))
    }
    $out += , @{ q = $qd; box = $box }
    $idx++
  }
  return , $out
}

$root = Split-Path -Parent $PSScriptRoot
$origDir = Join-Path $PSScriptRoot "orig"
$targets = @()
foreach ($job in $jobs) {
  if ($only -and $job.n -ne $only) { continue }
  $targets += , @{ n = $job.n; r = $job.r; base = $job.n }
  if ($job.n -match "^extra-(\d+)\.jpg$") {
    $num = [int]$Matches[1]
    if ($num -ge 21 -and $num -le 58) {
      $dup = "extra-$($num + 38).jpg"
      if (Test-Path (Join-Path $origDir $dup)) { $targets += , @{ n = $dup; r = $job.r; base = $job.n } }
    }
  }
}

if ($preview) {
  $cell = 520; $cols = 2; $per = 8; $ch = [int]($cell * 0.6)
  $cells = @()
  foreach ($t in $targets) {
    if ($t.n -ne $t.base) { continue }
    $bmp = Load24 (Join-Path $origDir $t.n)
    $quads = Get-Quads $bmp $t.base $t.r
    $idx = 0
    foreach ($qq in $quads) { $cells += , @{ n = "$($t.n)#$idx"; f = $t.n; q = $qq.q; box = $qq.box; W = $bmp.Width; H = $bmp.Height }; $idx++ }
    $bmp.Dispose()
  }
  $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(253, 104, 5)), 2
  $grid = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(110, 0, 255, 255)), 1
  $font = New-Object System.Drawing.Font "Arial", 9
  for ($page = 0; $page * $per -lt $cells.Count; $page++) {
    $slice = $cells[($page * $per)..([Math]::Min($cells.Count, ($page + 1) * $per) - 1)]
    $rows = [Math]::Ceiling($slice.Count / $cols)
    $sheet = New-Object System.Drawing.Bitmap ($cell * $cols), ($ch * $rows)
    $sg = [System.Drawing.Graphics]::FromImage($sheet)
    $sg.Clear([System.Drawing.Color]::Black)
    $i = 0
    foreach ($c in $slice) {
      $bmp = Load24 (Join-Path $origDir $c.f)
      $b = $c.box
      $cx = ($b[0] + $b[2] / 2) * $c.W; $cy = ($b[1] + $b[3] / 2) * $c.H
      $vw = [Math]::Max($b[2] * $c.W * 1.8, 160); $vh = $vw * 0.6
      $src = New-Object System.Drawing.RectangleF ([float]($cx - $vw / 2)), ([float]($cy - $vh / 2)), ([float]$vw), ([float]$vh)
      $ox = ($i % $cols) * $cell; $oy = [Math]::Floor($i / $cols) * $ch
      $sg.DrawImage($bmp, (New-Object System.Drawing.RectangleF $ox, $oy, $cell, $ch), $src, [System.Drawing.GraphicsUnit]::Pixel)
      $scale = $cell / $vw
      $stepX = 0.01
      for ($v = [Math]::Ceiling($src.X / $c.W / $stepX) * $stepX; $v * $c.W -lt $src.Right; $v += $stepX) {
        $x = $ox + ($v * $c.W - $src.X) * $scale
        $sg.DrawLine($grid, [float]$x, [float]$oy, [float]$x, [float]($oy + $ch))
        $sg.DrawString(("{0:0.00}" -f $v).Substring(1), $font, [System.Drawing.Brushes]::Yellow, [float]($x + 1), [float]($oy + $ch - 14))
      }
      for ($v = [Math]::Ceiling($src.Y / $c.H / $stepX) * $stepX; $v * $c.H -lt $src.Bottom; $v += $stepX) {
        $y = $oy + ($v * $c.H - $src.Y) * $scale
        $sg.DrawLine($grid, [float]$ox, [float]$y, [float]($ox + $cell), [float]$y)
        $sg.DrawString(("{0:0.00}" -f $v).Substring(1), $font, [System.Drawing.Brushes]::Yellow, [float]($ox + 1), [float]($y + 1))
      }
      if ($c.q) {
        $pts = @()
        for ($k = 0; $k -lt 8; $k += 2) {
          $pts += New-Object System.Drawing.PointF ([float]($ox + ($c.q[$k] - $src.X) * $scale)), ([float]($oy + ($c.q[$k + 1] - $src.Y) * $scale))
        }
        $sg.DrawPolygon($pen, [System.Drawing.PointF[]]$pts)
      }
      $label = $c.n + $(if (-not $c.q) { " NONE" } else { "" })
      $sg.FillRectangle([System.Drawing.Brushes]::Black, $ox + 30, $oy, 130, 14)
      $sg.DrawString($label, $font, [System.Drawing.Brushes]::White, $ox + 32, $oy)
      $bmp.Dispose()
      $i++
    }
    $sg.Dispose()
    $out = Join-Path $PSScriptRoot "detect-$page.jpg"
    $sheet.Save($out, $enc, $ep); $sheet.Dispose()
    Write-Output $out
  }
  return
}

foreach ($t in $targets) {
  $bmp = Load24 (Join-Path $origDir $t.n)
  $quads = Get-Quads $bmp $t.base $t.r
  foreach ($qq in $quads) { if ($qq.q) { [PlateMask1]::Apply($bmp, $qq.q) } }
  $path = Join-Path (Join-Path $root "assets") $t.n
  $tmp = $path + ".tmp.jpg"
  $bmp.Save($tmp, $enc, $ep); $bmp.Dispose()
  Move-Item -Force $tmp $path
  Write-Output $t.n
}
Write-Output "masked"

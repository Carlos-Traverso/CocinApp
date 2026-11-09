param([string]$Svg = "$PSScriptRoot\cocinapp_backend_uml.svg")
Add-Type -AssemblyName System.Drawing
[xml]$doc = Get-Content -LiteralPath $Svg -Raw -Encoding UTF8
$root = $doc.DocumentElement
$width = [int]$root.GetAttribute('width'); $height = [int]$root.GetAttribute('height')
$full = [System.Drawing.Bitmap]::new($width, $height)
$g = [System.Drawing.Graphics]::FromImage($full)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$g.Clear([System.Drawing.Color]::FromArgb(244,247,251))
function ColorOf([string]$s) {
  if (!$s -or $s -eq 'none') { return [System.Drawing.Color]::Transparent }
  if ($s.StartsWith('#')) { return [System.Drawing.ColorTranslator]::FromHtml($s) }
  return [System.Drawing.Color]::White
}
foreach ($n in $root.ChildNodes) {
  if ($n.NodeType -ne 'Element') { continue }
  switch ($n.LocalName) {
    'rect' {
      $x=0.0; $y=0.0; $w=0.0; $h=0.0
      if ($n.GetAttribute('x')) { $x=[float]$n.GetAttribute('x') }; if ($n.GetAttribute('y')) { $y=[float]$n.GetAttribute('y') }
      if ($n.GetAttribute('width') -eq '100%') { $w=$width } else { $w=[float]$n.GetAttribute('width') }
      if ($n.GetAttribute('height') -eq '100%') { $h=$height } else { $h=[float]$n.GetAttribute('height') }
      $fill=ColorOf $n.GetAttribute('fill')
      if ($fill.A -gt 0) { $b=[System.Drawing.SolidBrush]::new($fill); $g.FillRectangle($b,$x,$y,$w,$h); $b.Dispose() }
      $stroke=ColorOf $n.GetAttribute('stroke')
      if ($stroke.A -gt 0) { $p=[System.Drawing.Pen]::new($stroke,[Math]::Max(1,[float]$n.GetAttribute('stroke-width'))); $g.DrawRectangle($p,$x,$y,$w,$h); $p.Dispose() }
    }
    'line' {
      $c=ColorOf $n.GetAttribute('stroke'); $opacity=$n.GetAttribute('stroke-opacity'); if ($opacity) { $c=[System.Drawing.Color]::FromArgb([int](255*[double]$opacity),$c) }
      $p=[System.Drawing.Pen]::new($c,[Math]::Max(1,[float]$n.GetAttribute('stroke-width')))
      $g.DrawLine($p,[float]$n.GetAttribute('x1'),[float]$n.GetAttribute('y1'),[float]$n.GetAttribute('x2'),[float]$n.GetAttribute('y2')); $p.Dispose()
    }
    'circle' {
      $r=[float]$n.GetAttribute('r'); $x=[float]$n.GetAttribute('cx')-$r; $y=[float]$n.GetAttribute('cy')-$r
      $b=[System.Drawing.SolidBrush]::new((ColorOf $n.GetAttribute('fill'))); $g.FillEllipse($b,$x,$y,2*$r,2*$r); $b.Dispose()
    }
    'text' {
      $size=16.0; $weight=400; $family='Segoe UI'; $fill='#16283d'
      if ($n.GetAttribute('font-size')) { $size=[double]$n.GetAttribute('font-size') }
      if ($n.GetAttribute('font-weight')) { $weight=[int]$n.GetAttribute('font-weight') }
      if ($n.GetAttribute('font-family')) { $family=$n.GetAttribute('font-family').Split(',')[0].Trim(' ','"',"'") }
      if ($n.GetAttribute('fill')) { $fill=$n.GetAttribute('fill') }
      $fontStyle=[System.Drawing.FontStyle]::Regular; if ($weight -ge 600) { $fontStyle=[System.Drawing.FontStyle]::Bold }
      $font=[System.Drawing.Font]::new($family,[single]$size,$fontStyle,[System.Drawing.GraphicsUnit]::Pixel)
      $brush=[System.Drawing.SolidBrush]::new((ColorOf $fill)); $x=[single]$n.GetAttribute('x'); $y=[single]$n.GetAttribute('y')-[single]$size
      $str=$n.InnerText
      if ($n.GetAttribute('text-anchor') -eq 'end') { $m=$g.MeasureString($str,$font); $x-=$m.Width }
      elseif ($n.GetAttribute('text-anchor') -eq 'middle') { $m=$g.MeasureString($str,$font); $x-=$m.Width/2 }
      $g.DrawString($str,$font,$brush,$x,$y); $font.Dispose(); $brush.Dispose()
    }
  }
}
$dir=Split-Path -Parent $Svg
$full.Save((Join-Path $dir 'cocinapp_backend_uml.png'),[System.Drawing.Imaging.ImageFormat]::Png)
$preview=[System.Drawing.Bitmap]::new(1800,[int][Math]::Round(1800*$height/$width))
$pg=[System.Drawing.Graphics]::FromImage($preview); $pg.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic; $pg.DrawImage($full,0,0,$preview.Width,$preview.Height)
$preview.Save((Join-Path $dir 'cocinapp_backend_uml_preview.png'),[System.Drawing.Imaging.ImageFormat]::Png)
$pg.Dispose(); $preview.Dispose(); $g.Dispose(); $full.Dispose()

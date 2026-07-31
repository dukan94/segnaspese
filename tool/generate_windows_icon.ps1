# Ricostruisce windows/runner/resources/app_icon.ico con più risoluzioni
# (16/24/32/48/64/128/256) a partire da assets/icon/tally_icon.png.
#
# Necessario perché `dart run flutter_launcher_icons` genera per Windows
# un .ico con UNA sola risoluzione (quella di `icon_size` in pubspec.yaml,
# qui 256): risultato nitido a piena dimensione ma sfocato quando Windows
# lo scala per taskbar/Alt-Tab/finestra. Da rilanciare ogni volta dopo
# `dart run flutter_launcher_icons`, se cambia l'icona sorgente.
#
# Uso: powershell -File tool/generate_windows_icon.ps1

Add-Type -AssemblyName System.Drawing

$repoRoot = Split-Path -Parent $PSScriptRoot
$srcPath = Join-Path $repoRoot "assets\icon\tally_icon.png"
$outPath = Join-Path $repoRoot "windows\runner\resources\app_icon.ico"

$src = [System.Drawing.Image]::FromFile($srcPath)
$sizes = @(16, 24, 32, 48, 64, 128, 256)

$pngBlobs = @()
foreach ($s in $sizes) {
    $bmp = New-Object System.Drawing.Bitmap($s, $s)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.DrawImage($src, 0, 0, $s, $s)
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $pngBlobs += ,($s, $ms.ToArray())
    $g.Dispose(); $bmp.Dispose(); $ms.Dispose()
}

$out = New-Object System.IO.MemoryStream
$writer = New-Object System.IO.BinaryWriter($out)

$writer.Write([UInt16]0)      # reserved
$writer.Write([UInt16]1)      # type = icon
$writer.Write([UInt16]$pngBlobs.Count)

$headerSize = 6 + 16 * $pngBlobs.Count
$offset = $headerSize
$entries = @()
foreach ($item in $pngBlobs) {
    $s = $item[0]; $bytes = $item[1]
    $entries += ,@{ size = $s; bytes = $bytes; offset = $offset }
    $offset += $bytes.Length
}

foreach ($e in $entries) {
    $dim = if ($e.size -eq 256) { 0 } else { $e.size }   # 0 = 256 per spec ICO
    $writer.Write([byte]$dim)
    $writer.Write([byte]$dim)
    $writer.Write([byte]0)
    $writer.Write([byte]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]32)
    $writer.Write([UInt32]$e.bytes.Length)
    $writer.Write([UInt32]$e.offset)
}
foreach ($e in $entries) {
    $writer.Write($e.bytes)
}

$writer.Flush()
[System.IO.File]::WriteAllBytes($outPath, $out.ToArray())
Write-Output "Scritto $outPath con $($entries.Count) risoluzioni ($($sizes -join ', '))"

$writer.Dispose(); $out.Dispose(); $src.Dispose()

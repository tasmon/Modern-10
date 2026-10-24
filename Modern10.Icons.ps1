# Modern10.Icons.ps1  -  dot-sourced by Modern10.ps1 and Modern10-GUI.ps1
# Draws macOS-inspired glass icons with System.Drawing and writes multi-size .ico files.
# Nothing is downloaded; everything is vector-drawn on a 256 x 256 canvas.

Add-Type -AssemblyName System.Drawing

$script:M10IconKinds = @(
    'Folder', 'FolderOpen', 'ThisPC', 'Drive', 'RecycleEmpty', 'RecycleFull',
    'User', 'Network', 'ControlPanel',
    'Documents', 'Downloads', 'Pictures', 'Music', 'Videos', 'Desktop'
)

function New-M10Col([string]$Hex, [int]$A = 255) {
    $h = $Hex.TrimStart('#')
    return [System.Drawing.Color]::FromArgb($A,
        [Convert]::ToInt32($h.Substring(0, 2), 16),
        [Convert]::ToInt32($h.Substring(2, 2), 16),
        [Convert]::ToInt32($h.Substring(4, 2), 16))
}

function Get-M10Palette([string]$Theme) {
    if ($Theme -eq 'Light') {
        return @{
            FB1 = (New-M10Col '#5E9BF0'); FB2 = (New-M10Col '#3E80E0')     # folder back
            FF1 = (New-M10Col '#9ED0FF'); FF2 = (New-M10Col '#5AA8F8')     # folder front
            M1  = (New-M10Col '#FFFFFF'); M2  = (New-M10Col '#B4BDCC')     # brushed metal
            S1  = (New-M10Col '#9CD0FF'); S2  = (New-M10Col '#C9B0FF')     # screen
            A1  = (New-M10Col '#7CC4FF'); A2  = (New-M10Col '#007AFF')     # accent
            G1  = (New-M10Col '#B7BFCD'); G2  = (New-M10Col '#7C8596')     # gray
            Z1  = (New-M10Col '#E8ECF2'); Z2  = (New-M10Col '#B9C0CC')     # bezel
        }
    }
    return @{
        FB1 = (New-M10Col '#2A5FC4'); FB2 = (New-M10Col '#1E4BA3')
        FF1 = (New-M10Col '#58A6FF'); FF2 = (New-M10Col '#2F7BEA')
        M1  = (New-M10Col '#DDE3EC'); M2  = (New-M10Col '#8E98AA')
        S1  = (New-M10Col '#5E5CE6'); S2  = (New-M10Col '#0A84FF')
        A1  = (New-M10Col '#5AB0FF'); A2  = (New-M10Col '#0A84FF')
        G1  = (New-M10Col '#8E96A6'); G2  = (New-M10Col '#4A505E')
        Z1  = (New-M10Col '#3A3F4A'); Z2  = (New-M10Col '#1B1E25')
    }
}

# ---------------------------------------------------------------- helpers
function New-M10RoundPath([double]$X, [double]$Y, [double]$W, [double]$H, [double]$R) {
    $d = 2 * $R
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddArc([single]$X, [single]$Y, [single]$d, [single]$d, 180, 90)
    $p.AddArc([single]($X + $W - $d), [single]$Y, [single]$d, [single]$d, 270, 90)
    $p.AddArc([single]($X + $W - $d), [single]($Y + $H - $d), [single]$d, [single]$d, 0, 90)
    $p.AddArc([single]$X, [single]($Y + $H - $d), [single]$d, [single]$d, 90, 90)
    $p.CloseFigure()
    return $p
}

function New-M10Points([double[]]$Coords) {
    $pts = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    for ($i = 0; $i -lt $Coords.Count; $i += 2) {
        $pts.Add((New-Object System.Drawing.PointF([single]$Coords[$i], [single]$Coords[$i + 1])))
    }
    return , $pts.ToArray()
}

function Add-M10Fill($G, $Path, $C1, $C2, [single]$Angle = 90) {
    $rb = $Path.GetBounds()
    $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rb, $C1, $C2, $Angle)
    $G.FillPath($br, $Path)
    $br.Dispose()
}

function Add-M10Gloss($G, $Path, [int]$Alpha = 80) {
    $rb = $Path.GetBounds()
    $r = New-Object System.Drawing.RectangleF($rb.X, $rb.Y, $rb.Width, [single]($rb.Height * 0.55))
    $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush($r, (New-M10Col '#FFFFFF' $Alpha), (New-M10Col '#FFFFFF' 0), [single]90)
    $G.SetClip($Path)
    $G.FillRectangle($br, $r)
    $G.ResetClip()
    $br.Dispose()
}

function Add-M10Shadow($G, [double]$X, [double]$Y, [double]$W, [double]$H, [double]$R) {
    for ($i = 0; $i -lt 6; $i++) {
        $e = $i * 3
        $a = [int](28 - $i * 4)
        $p = New-M10RoundPath ($X - $e) ($Y - $e + 10) ($W + 2 * $e) ($H + 2 * $e) ($R + $e)
        $br = New-Object System.Drawing.SolidBrush((New-M10Col '#000000' $a))
        $G.FillPath($br, $p)
        $br.Dispose(); $p.Dispose()
    }
}

function Add-M10Stroke($G, $Path, $Color, [single]$Width) {
    $pen = New-Object System.Drawing.Pen($Color, $Width)
    $pen.LineJoin = 'Round'
    $G.DrawPath($pen, $Path)
    $pen.Dispose()
}

# ---------------------------------------------------------------- glyphs for user folders
function Draw-M10Glyph($G, [string]$Glyph, $P) {
    $white = New-Object System.Drawing.SolidBrush((New-M10Col '#FFFFFF' 238))
    $tint  = New-Object System.Drawing.SolidBrush((New-M10Col '#2F7BEA' 210))
    switch ($Glyph) {
        'Documents' {
            $pg = New-M10RoundPath 102 116 52 68 7
            $G.FillPath($white, $pg); $pg.Dispose()
            foreach ($i in 0..2) { $G.FillRectangle($tint, 110, (132 + $i * 14), 36, 5) }
        }
        'Downloads' {
            $G.FillPolygon($white, (New-M10Points @(118,114, 138,114, 138,146, 158,146, 128,184, 98,146, 118,146)))
        }
        'Pictures' {
            $fr = New-M10RoundPath 96 118 64 52 8
            $G.FillPath($white, $fr); $fr.Dispose()
            $G.FillEllipse($tint, 134, 126, 12, 12)
            $G.FillPolygon($tint, (New-M10Points @(102,166, 120,138, 134,156, 144,146, 154,166)))
        }
        'Music' {
            $G.FillEllipse($white, 102, 160, 26, 20)
            $G.FillEllipse($white, 134, 150, 26, 20)
            $G.FillRectangle($white, 122, 118, 6, 52)
            $G.FillRectangle($white, 154, 108, 6, 52)
            $G.FillPolygon($white, (New-M10Points @(122,118, 160,108, 160,124, 122,134)))
        }
        'Videos' {
            $G.FillPolygon($white, (New-M10Points @(112,118, 112,186, 168,152)))
        }
        'Desktop' {
            $mon = New-M10RoundPath 96 120 64 42 6
            $G.FillPath($white, $mon); $mon.Dispose()
            $G.FillRectangle($tint, 102, 126, 52, 30)
            $G.FillRectangle($white, 122, 164, 12, 8)
            $base = New-M10RoundPath 108 172 40 6 3
            $G.FillPath($white, $base); $base.Dispose()
        }
    }
    $white.Dispose(); $tint.Dispose()
}

# ---------------------------------------------------------------- icon bodies
function Draw-M10Folder($G, $P, [bool]$Open, [string]$Glyph) {
    Add-M10Shadow $G 24 72 208 146 18
    $tab = New-M10RoundPath 24 44 104 56 14
    Add-M10Fill $G $tab $P.FB1 $P.FB2
    $back = New-M10RoundPath 24 62 208 150 18
    Add-M10Fill $G $back $P.FB1 $P.FB2

    if ($Open) {
        $paper = New-M10RoundPath 46 54 164 120 8
        Add-M10Fill $G $paper (New-M10Col '#FFFFFF') (New-M10Col '#D9E0EA')
        $paper.Dispose()
        $pts = New-M10Points @(50,104, 230,104, 216,212, 30,212)
        $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.RectangleF(22, 96, 220, 124)), $P.FF1, $P.FF2, [single]90)
        $G.FillPolygon($br, $pts)
        $pen = New-Object System.Drawing.Pen($br, 12)
        $pen.LineJoin = 'Round'
        $G.DrawPolygon($pen, $pts)
        $pen.Dispose(); $br.Dispose()
        $front = New-Object System.Drawing.Drawing2D.GraphicsPath
        $front.AddPolygon((New-M10Points @(44,98, 236,98, 224,218, 28,218)))
        Add-M10Gloss $G $front 70
        $front.Dispose()
    } else {
        $front = New-M10RoundPath 24 88 208 130 18
        Add-M10Fill $G $front $P.FF1 $P.FF2
        Add-M10Gloss $G $front 80
        $hl = New-Object System.Drawing.Pen((New-M10Col '#FFFFFF' 110), 2)
        $G.DrawLine($hl, 40, 90, 216, 90)
        $hl.Dispose()
        $front.Dispose()
    }
    if ($Glyph) { Draw-M10Glyph $G $Glyph $P }
    $tab.Dispose(); $back.Dispose()
}

function Draw-M10ThisPC($G, $P) {
    Add-M10Shadow $G 36 40 184 130 14
    $bezel = New-M10RoundPath 36 36 184 128 14
    Add-M10Fill $G $bezel $P.Z1 $P.Z2
    $scr = New-M10RoundPath 46 46 164 106 8
    Add-M10Fill $G $scr $P.S1 $P.S2 45
    $G.SetClip($scr)
    $br = New-Object System.Drawing.SolidBrush((New-M10Col '#FFFFFF' 42))
    $G.FillPolygon($br, (New-M10Points @(46,46, 150,46, 100,152, 46,152)))
    $br.Dispose()
    $G.ResetClip()
    $neck = New-Object System.Drawing.Drawing2D.GraphicsPath
    $neck.AddPolygon((New-M10Points @(112,164, 144,164, 152,206, 104,206)))
    Add-M10Fill $G $neck $P.M1 $P.M2
    $base = New-M10RoundPath 80 204 96 14 7
    Add-M10Fill $G $base $P.M1 $P.M2
    $bezel.Dispose(); $scr.Dispose(); $neck.Dispose(); $base.Dispose()
}

function Draw-M10Drive($G, $P) {
    Add-M10Shadow $G 28 84 200 102 18
    $body = New-M10RoundPath 28 80 200 104 18
    Add-M10Fill $G $body $P.M1 $P.M2
    Add-M10Gloss $G $body 90
    Add-M10Stroke $G $body (New-M10Col '#000000' 40) 2
    $strip = New-M10RoundPath 40 146 176 26 10
    $sb = New-Object System.Drawing.SolidBrush((New-M10Col '#000000' 32))
    $G.FillPath($sb, $strip)
    $sb.Dispose()
    $pen = New-Object System.Drawing.Pen((New-M10Col '#000000' 90), 5)
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
    $G.DrawLine($pen, 56, 159, 130, 159)
    $pen.Dispose()
    $led = New-Object System.Drawing.SolidBrush((New-M10Col '#34C759'))
    $G.FillEllipse($led, 188, 153, 12, 12)
    $led.Dispose()
    $body.Dispose(); $strip.Dispose()
}

function Draw-M10Bin($G, $P, [bool]$Full) {
    Add-M10Shadow $G 70 110 116 106 12
    if ($Full) {
        $pen = New-Object System.Drawing.Pen((New-M10Col '#000000' 50), 2)
        $paper1 = New-M10Points @(80,96, 98,54, 122,80, 142,44, 166,80, 184,60, 178,96)
        $b1 = New-Object System.Drawing.SolidBrush((New-M10Col '#FFFFFF'))
        $G.FillPolygon($b1, $paper1); $G.DrawPolygon($pen, $paper1)
        $paper2 = New-M10Points @(96,96, 116,68, 136,92, 156,60, 172,96)
        $b2 = New-Object System.Drawing.SolidBrush((New-M10Col '#7CC4FF' 235))
        $G.FillPolygon($b2, $paper2); $G.DrawPolygon($pen, $paper2)
        $b1.Dispose(); $b2.Dispose(); $pen.Dispose()
    }
    $inner = New-M10Points @(75,97, 181,97, 170,209, 86,209)
    $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.RectangleF(70, 92, 116, 122)), $P.M1, $P.M2, [single]0)
    $G.FillPolygon($br, $inner)
    $edge = New-Object System.Drawing.Pen($P.M2, 10)
    $edge.LineJoin = 'Round'
    $G.DrawPolygon($edge, $inner)
    $edge.Dispose(); $br.Dispose()
    $lp = New-Object System.Drawing.Pen((New-M10Col '#000000' 55), 5)
    $lp.StartCap = 'Round'; $lp.EndCap = 'Round'
    foreach ($x in 100, 128, 156) { $G.DrawLine($lp, $x, 112, $x, 198) }
    $lp.Dispose()
    $lid = New-M10RoundPath 58 70 140 22 11
    Add-M10Fill $G $lid $P.M1 $P.M2
    Add-M10Gloss $G $lid 90
    Add-M10Stroke $G $lid (New-M10Col '#000000' 40) 2
    $lid.Dispose()
    if (-not $Full) {
        $h = New-M10RoundPath 104 52 48 22 10
        Add-M10Stroke $G $h $P.M2 8
        $h.Dispose()
    }
}

function Draw-M10User($G, $P) {
    Add-M10Shadow $G 28 28 200 200 50
    $sq = New-M10RoundPath 28 24 200 200 50
    Add-M10Fill $G $sq $P.A1 $P.A2
    $G.SetClip($sq)
    $w = New-Object System.Drawing.SolidBrush((New-M10Col '#FFFFFF' 240))
    $G.FillEllipse($w, 94, 62, 68, 68)
    $G.FillEllipse($w, 52, 148, 152, 130)
    $w.Dispose()
    $G.ResetClip()
    Add-M10Gloss $G $sq 60
    $sq.Dispose()
}

function Draw-M10Network($G, $P) {
    $sh = New-Object System.Drawing.SolidBrush((New-M10Col '#000000' 40))
    $G.FillEllipse($sh, 44, 214, 168, 18)
    $sh.Dispose()
    $c = New-Object System.Drawing.Drawing2D.GraphicsPath
    $c.AddEllipse(28, 24, 200, 200)
    Add-M10Fill $G $c $P.A1 $P.A2
    $G.SetClip($c)
    $pen = New-Object System.Drawing.Pen((New-M10Col '#FFFFFF' 135), 6)
    $G.DrawEllipse($pen, 60, 24, 136, 200)
    $G.DrawEllipse($pen, 100, 24, 56, 200)
    $G.DrawLine($pen, 128, 24, 128, 224)
    foreach ($y in 84, 124, 164) { $G.DrawLine($pen, 28, $y, 228, $y) }
    $pen.Dispose()
    $hl = New-Object System.Drawing.SolidBrush((New-M10Col '#FFFFFF' 55))
    $G.FillEllipse($hl, 50, 32, 120, 72)
    $hl.Dispose()
    $G.ResetClip()
    $c.Dispose()
}

function Draw-M10Control($G, $P) {
    Add-M10Shadow $G 28 28 200 200 50
    $sq = New-M10RoundPath 28 24 200 200 50
    Add-M10Fill $G $sq $P.G1 $P.G2
    $pts = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    for ($i = 0; $i -lt 8; $i++) {
        $a = $i * [Math]::PI / 4
        foreach ($d in @(@(-0.30, 55), @(-0.17, 72), @(0.17, 72), @(0.30, 55))) {
            $ang = $a + $d[0]
            $r = $d[1]
            $pts.Add((New-Object System.Drawing.PointF([single](128 + $r * [Math]::Cos($ang)), [single](124 + $r * [Math]::Sin($ang)))))
        }
    }
    $gear = New-Object System.Drawing.Drawing2D.GraphicsPath
    $gear.AddPolygon($pts.ToArray())
    Add-M10Fill $G $gear (New-M10Col '#FFFFFF') (New-M10Col '#D3D9E3')
    $hole = New-Object System.Drawing.SolidBrush($P.G2)
    $G.FillEllipse($hole, 104, 100, 48, 48)
    $hole.Dispose()
    Add-M10Gloss $G $sq 50
    $sq.Dispose(); $gear.Dispose()
}

# ---------------------------------------------------------------- public API
function New-M10IconBitmap([string]$Kind, [int]$Size, [string]$Theme = 'Dark') {
    $P = Get-M10Palette $Theme
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.PixelOffsetMode = 'HighQuality'
    $g.CompositingQuality = 'HighQuality'
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.ScaleTransform([single]($Size / 256), [single]($Size / 256))

    switch ($Kind) {
        'Folder'       { Draw-M10Folder $g $P $false '' }
        'FolderOpen'   { Draw-M10Folder $g $P $true '' }
        'ThisPC'       { Draw-M10ThisPC $g $P }
        'Drive'        { Draw-M10Drive $g $P }
        'RecycleEmpty' { Draw-M10Bin $g $P $false }
        'RecycleFull'  { Draw-M10Bin $g $P $true }
        'User'         { Draw-M10User $g $P }
        'Network'      { Draw-M10Network $g $P }
        'ControlPanel' { Draw-M10Control $g $P }
        'Documents'    { Draw-M10Folder $g $P $false 'Documents' }
        'Downloads'    { Draw-M10Folder $g $P $false 'Downloads' }
        'Pictures'     { Draw-M10Folder $g $P $false 'Pictures' }
        'Music'        { Draw-M10Folder $g $P $false 'Music' }
        'Videos'       { Draw-M10Folder $g $P $false 'Videos' }
        'Desktop'      { Draw-M10Folder $g $P $false 'Desktop' }
        default        { Draw-M10Folder $g $P $false '' }
    }
    $g.Dispose()
    return , $bmp
}

# Writes a multi-size .ico (PNG-compressed entries, supported by Windows Vista and newer)
function Save-M10Ico([string]$Path, [string]$Kind, [string]$Theme = 'Dark') {
    $sizes = @(16, 24, 32, 48, 64, 128, 256)
    $blobs = @()
    foreach ($s in $sizes) {
        $bmp = New-M10IconBitmap $Kind $s $Theme
        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $blobs += , ($ms.ToArray())
        $ms.Dispose(); $bmp.Dispose()
    }
    $fs = [System.IO.File]::Create($Path)
    $bw = New-Object System.IO.BinaryWriter($fs)
    try {
        $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
        $offset = 6 + 16 * $sizes.Count
        for ($i = 0; $i -lt $sizes.Count; $i++) {
            $dim = $sizes[$i]; if ($dim -ge 256) { $dim = 0 }
            $bw.Write([byte]$dim); $bw.Write([byte]$dim)
            $bw.Write([byte]0); $bw.Write([byte]0)
            $bw.Write([uint16]1); $bw.Write([uint16]32)
            $bw.Write([uint32]$blobs[$i].Length)
            $bw.Write([uint32]$offset)
            $offset += $blobs[$i].Length
        }
        foreach ($b in $blobs) { $bw.Write([byte[]]$b) }
    } finally {
        $bw.Close(); $fs.Close()
    }
}

function New-M10IconSet([string]$Dir, [string]$Theme) {
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    foreach ($k in $script:M10IconKinds) {
        Save-M10Ico -Path (Join-Path $Dir "$k.ico") -Kind $k -Theme $Theme
    }
}

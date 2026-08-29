# ============================================================
#  PIXEL SHUTDOWN / HIBERNATE SCHEDULER
#  version 8.29.1
# ============================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Opt out of DPI virtualization: Windows would bitmap-stretch the window and
# blur every pixel. Instead we stay 1:1 with the screen and scale $U ourselves,
# so the art stays sharp at any display scaling.
Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();' `
    -Name 'DpiApi' -Namespace 'PixelSched' -ErrorAction SilentlyContinue
try { [PixelSched.DpiApi]::SetProcessDPIAware() | Out-Null } catch { }

$APP_VERSION = '8.29.1'

# device pixels per layout unit (also one font pixel) - integer, so pixels stay square
$gfxProbe = [Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
$U = [int][Math]::Max(4, [Math]::Round(4 * ($gfxProbe.DpiX / 96.0)))
$gfxProbe.Dispose()

# ------------------------------------------------------------ palette
$PALETTE = @{
    ink   = '#22222E'
    bg    = '#F3ECE0'
    panel = '#FFFBF2'
    teal  = '#7FC8C0'
    coral = '#F2A08E'
    blue  = '#9CBEEA'
    green = '#A8D98B'
    amber = '#F5CE7A'
    dim   = '#DDD4C5'
    muted = '#8A8172'
    rose  = '#DE6A5B'
}
$BRUSH = @{}
foreach ($k in $PALETTE.Keys) {
    $BRUSH[$k] = New-Object Drawing.SolidBrush ([Drawing.ColorTranslator]::FromHtml($PALETTE[$k]))
}

# ------------------------------------------------------------ 5x7 bitmap font
$FONT_DATA = @'
0|.###.|#...#|#..##|#.#.#|##..#|#...#|.###.
1|..#..|.##..|..#..|..#..|..#..|..#..|.###.
2|.###.|#...#|....#|...#.|..#..|.#...|#####
3|#####|...#.|..#..|...#.|....#|#...#|.###.
4|...#.|..##.|.#.#.|#..#.|#####|...#.|...#.
5|#####|#....|####.|....#|....#|#...#|.###.
6|..##.|.#...|#....|####.|#...#|#...#|.###.
7|#####|....#|...#.|..#..|.#...|.#...|.#...
8|.###.|#...#|#...#|.###.|#...#|#...#|.###.
9|.###.|#...#|#...#|.####|....#|...#.|.##..
A|.###.|#...#|#...#|#####|#...#|#...#|#...#
B|####.|#...#|#...#|####.|#...#|#...#|####.
C|.###.|#...#|#....|#....|#....|#...#|.###.
D|###..|#..#.|#...#|#...#|#...#|#..#.|###..
E|#####|#....|#....|####.|#....|#....|#####
F|#####|#....|#....|####.|#....|#....|#....
G|.###.|#...#|#....|#.###|#...#|#...#|.###.
H|#...#|#...#|#...#|#####|#...#|#...#|#...#
I|.###.|..#..|..#..|..#..|..#..|..#..|.###.
J|..###|...#.|...#.|...#.|...#.|#..#.|.##..
K|#...#|#..#.|#.#..|##...|#.#..|#..#.|#...#
L|#....|#....|#....|#....|#....|#....|#####
M|#...#|##.##|#.#.#|#.#.#|#...#|#...#|#...#
N|#...#|##..#|#.#.#|#..##|#...#|#...#|#...#
O|.###.|#...#|#...#|#...#|#...#|#...#|.###.
P|####.|#...#|#...#|####.|#....|#....|#....
Q|.###.|#...#|#...#|#...#|#.#.#|#..#.|.##.#
R|####.|#...#|#...#|####.|#.#..|#..#.|#...#
S|.####|#....|#....|.###.|....#|....#|####.
T|#####|..#..|..#..|..#..|..#..|..#..|..#..
U|#...#|#...#|#...#|#...#|#...#|#...#|.###.
V|#...#|#...#|#...#|#...#|#...#|.#.#.|..#..
W|#...#|#...#|#...#|#.#.#|#.#.#|##.##|#...#
X|#...#|#...#|.#.#.|..#..|.#.#.|#...#|#...#
Y|#...#|#...#|.#.#.|..#..|..#..|..#..|..#..
Z|#####|....#|...#.|..#..|.#...|#....|#####
:|.....|..#..|..#..|.....|..#..|..#..|.....
-|.....|.....|.....|#####|.....|.....|.....
+|.....|..#..|..#..|#####|..#..|..#..|.....
/|....#|....#|...#.|..#..|.#...|#....|#....
.|.....|.....|.....|.....|.....|..#..|..#..
!|..#..|..#..|..#..|..#..|..#..|.....|..#..
'@

$FONT = @{}
foreach ($line in ($FONT_DATA -split "`r?`n")) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $p = $line -split '\|'
    $FONT[$p[0]] = $p[1..7]
}

# ------------------------------------------------------------ layout (in units)
$W = 123; $H = 70
$ROW_Y = 21; $ROW_H = 13; $TXT_Y = 24
$BOX = @{
    time = @{ x = 6;  w = 35 }
    ampm = @{ x = 43; w = 17 }
    s    = @{ x = 62; w = 11 }
    h    = @{ x = 75; w = 11 }
    act  = @{ x = 88; w = 29 }
}
$SEG_HOUR = @{ x = 8;  w = 13 }
$SEG_MIN  = @{ x = 26; w = 13 }

# ------------------------------------------------------------ state
$state = @{
    hour      = 6
    minute    = 0
    ampm      = 'PM'
    action    = 'S'
    phase     = 'idle'      # idle | armed | fired
    target    = $null
    sel       = 'hour'      # hour | min | ampm | mode
    hover     = ''
    status    = 'READY'
    stcol     = 'muted'
    lastLabel = ''
}

# ------------------------------------------------------------ drawing helpers
function Fill-U {
    param($g, [string]$color, [double]$x, [double]$y, [double]$w, [double]$h)
    $g.FillRectangle($BRUSH[$color], [int]($x * $U), [int]($y * $U), [int]($w * $U), [int]($h * $U))
}

function Draw-Text {
    param($g, [string]$text, [double]$x, [double]$y, [string]$color, [double]$scale = 1)
    $b  = $BRUSH[$color]
    $px = [int]($scale * $U)
    $cx = [int]($x * $U)
    $py = [int]($y * $U)
    foreach ($ch in $text.ToUpper().ToCharArray()) {
        $key = [string]$ch
        if ($FONT.ContainsKey($key)) {
            $rows = $FONT[$key]
            for ($r = 0; $r -lt 7; $r++) {
                $row = $rows[$r]
                for ($c = 0; $c -lt 5; $c++) {
                    if ($row[$c] -eq '#') {
                        $g.FillRectangle($b, $cx + $c * $px, $py + $r * $px, $px, $px)
                    }
                }
            }
        }
        $cx += 6 * $px
    }
}

function Text-Width { param([string]$t, [double]$scale = 1) ($t.Length * 6 - 1) * $scale }

function Draw-Box {
    param($g, [double]$x, [double]$y, [double]$w, [double]$h, [string]$fill, [bool]$shadow = $true)
    if ($shadow) { Fill-U $g 'ink' ($x + 1) ($y + 1) $w $h }
    Fill-U $g 'ink' $x $y $w $h
    Fill-U $g $fill ($x + 1) ($y + 1) ($w - 2) ($h - 2)
}

function Draw-Centered {
    param($g, [string]$text, [double]$bx, [double]$bw, [double]$y, [string]$color)
    $tw = Text-Width $text 1
    Draw-Text $g $text ($bx + [Math]::Floor(($bw - $tw) / 2)) $y $color 1
}

# ------------------------------------------------------------ logic
function Get-Target {
    $h24 = $state.hour % 12
    if ($state.ampm -eq 'PM') { $h24 += 12 }
    $now = Get-Date
    $t = $now.Date.AddHours($h24).AddMinutes($state.minute)
    if ($t -le $now) { $t = $t.AddDays(1) }
    return $t
}

function Adjust-Segment {
    param([string]$seg, [int]$dir, [bool]$fine = $false)
    switch ($seg) {
        'hour' { $state.hour = ((($state.hour - 1 + $dir) % 12) + 12) % 12 + 1 }
        'min'  {
            $step = if ($fine) { 1 } else { 5 }
            if (-not $fine) { $state.minute = [Math]::Floor($state.minute / 5) * 5 }
            $state.minute = ((($state.minute + $dir * $step) % 60) + 60) % 60
        }
        'ampm' { $state.ampm = $(if ($state.ampm -eq 'AM') { 'PM' } else { 'AM' }) }
        'mode' { $state.action = $(if ($state.action -eq 'S') { 'H' } else { 'S' }) }
    }
}

function Set-Status { param([string]$t, [string]$c = 'muted') $state.status = $t; $state.stcol = $c }

function Arm-Timer {
    $state.target    = Get-Target
    $state.phase     = 'armed'
    $state.lastLabel = ''
    $timer.Start()
    Update-Countdown
}

function Disarm-Timer {
    param([bool]$abort = $false)
    $timer.Stop()
    if ($abort -and $state.phase -eq 'fired' -and $state.action -eq 'S') {
        Start-Process -FilePath 'shutdown.exe' -ArgumentList '/a' -WindowStyle Hidden -ErrorAction SilentlyContinue
    }
    if ($state.phase -ne 'idle') { Set-Status 'READY' 'muted' }
    $state.phase     = 'idle'
    $state.target    = $null
    $state.lastLabel = ''
}

function Fire-Action {
    $timer.Stop()
    $state.phase = 'fired'
    try {
        if ($state.action -eq 'S') {
            Start-Process -FilePath 'shutdown.exe' -ArgumentList '/s', '/f', '/t', '20' `
                -WindowStyle Hidden -PassThru -Wait -ErrorAction Stop | Out-Null
            Set-Status 'BYE IN 20 SEC' 'rose'
        } else {
            $p = Start-Process -FilePath 'shutdown.exe' -ArgumentList '/h' `
                -WindowStyle Hidden -PassThru -Wait -ErrorAction Stop
            $state.phase = 'idle'
            if ($p.ExitCode -ne 0) { Set-Status 'HIBERNATE OFF' 'rose' } else { Set-Status 'READY' 'muted' }
        }
    } catch {
        $state.phase = 'idle'
        Set-Status 'FAILED' 'rose'
    }
    $canvas.Invalidate()
}

function Update-Countdown {
    if ($state.phase -ne 'armed') { return }
    $left = $state.target - (Get-Date)
    if ($left.TotalSeconds -le 0) { Fire-Action; return }
    $label = '{0:00}:{1:00}:{2:00}' -f [int]$left.TotalHours, $left.Minutes, $left.Seconds
    $word  = $(if ($state.action -eq 'S') { 'OFF' } else { 'HIB' })
    $txt   = "$word IN $label"
    if ($txt -ne $state.lastLabel) {
        $state.lastLabel = $txt
        Set-Status $txt 'teal'
        $canvas.Invalidate()
    }
}

# ------------------------------------------------------------ form + canvas
$form = New-Object Windows.Forms.Form
$form.Text            = "SHUTDOWN SCHEDULER v$APP_VERSION"
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox     = $false
$form.StartPosition   = 'CenterScreen'
$form.ClientSize      = New-Object Drawing.Size (($W * $U), ($H * $U))
$form.BackColor       = [Drawing.ColorTranslator]::FromHtml($PALETTE.bg)
$form.KeyPreview      = $true

$canvas = New-Object Windows.Forms.Panel
$canvas.Dock      = 'Fill'
$canvas.BackColor = [Drawing.ColorTranslator]::FromHtml($PALETTE.bg)
$canvas.TabStop   = $true
[Windows.Forms.Control].GetProperty('DoubleBuffered', [Reflection.BindingFlags]'Instance,NonPublic').SetValue($canvas, $true, $null)
$form.Controls.Add($canvas)

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 200

# ------------------------------------------------------------ paint
$canvas.Add_Paint({
    $g = $_.Graphics
    $g.SmoothingMode   = 'None'
    $g.PixelOffsetMode = 'Half'

    # frame
    Fill-U $g 'ink' 0 0 $W $H
    Fill-U $g 'bg'  2 2 ($W - 4) ($H - 4)

    # title
    Draw-Text $g 'SET TIME' 6 6 'ink' 1
    $vtag = "V$APP_VERSION"
    Draw-Text $g $vtag ($W - 6 - (Text-Width $vtag 0.5)) 9 'muted' 0.5

    # time box
    Draw-Box $g $BOX.time.x $ROW_Y $BOX.time.w $ROW_H 'panel'
    if ($state.hover -eq 'hour') { Fill-U $g 'amber' $SEG_HOUR.x ($ROW_Y + 1) $SEG_HOUR.w ($ROW_H - 2) }
    if ($state.hover -eq 'min')  { Fill-U $g 'amber' $SEG_MIN.x  ($ROW_Y + 1) $SEG_MIN.w  ($ROW_H - 2) }
    Draw-Text $g ('{0:00}:{1:00}' -f $state.hour, $state.minute) 9 $TXT_Y 'ink' 1

    # am / pm
    $ampmFill = $(if ($state.hover -eq 'ampm') { 'amber' } else { 'teal' })
    Draw-Box $g $BOX.ampm.x $ROW_Y $BOX.ampm.w $ROW_H $ampmFill
    Draw-Centered $g $state.ampm $BOX.ampm.x $BOX.ampm.w $TXT_Y 'ink'

    # S / H
    $sFill = $(if ($state.action -eq 'S') { 'coral' } elseif ($state.hover -eq 's') { 'amber' } else { 'dim' })
    $hFill = $(if ($state.action -eq 'H') { 'blue' }  elseif ($state.hover -eq 'h') { 'amber' } else { 'dim' })
    Draw-Box $g $BOX.s.x $ROW_Y $BOX.s.w $ROW_H $sFill
    Draw-Box $g $BOX.h.x $ROW_Y $BOX.h.w $ROW_H $hFill
    Draw-Centered $g 'S' $BOX.s.x $BOX.s.w $TXT_Y $(if ($state.action -eq 'S') { 'ink' } else { 'muted' })
    Draw-Centered $g 'H' $BOX.h.x $BOX.h.w $TXT_Y $(if ($state.action -eq 'H') { 'ink' } else { 'muted' })

    # action button
    switch ($state.phase) {
        'armed' { $actLabel = 'STOP';  $actFill = 'rose' }
        'fired' { $actLabel = 'ABORT'; $actFill = 'rose' }
        default { $actLabel = 'SET';   $actFill = 'green' }
    }
    if ($state.hover -eq 'act') { $actFill = 'amber' }
    Draw-Box $g $BOX.act.x $ROW_Y $BOX.act.w $ROW_H $actFill
    Draw-Centered $g $actLabel $BOX.act.x $BOX.act.w $TXT_Y 'ink'

    # selection underline
    $ul = $null
    switch ($state.sel) {
        'hour' { $ul = @{ x = $SEG_HOUR.x; w = $SEG_HOUR.w } }
        'min'  { $ul = @{ x = $SEG_MIN.x;  w = $SEG_MIN.w } }
        'ampm' { $ul = @{ x = $BOX.ampm.x + 2; w = $BOX.ampm.w - 4 } }
        'mode' {
            $mb = $(if ($state.action -eq 'S') { $BOX.s } else { $BOX.h })
            $ul = @{ x = $mb.x + 2; w = $mb.w - 4 }
        }
    }
    if ($ul) { Fill-U $g 'ink' $ul.x ($ROW_Y + $ROW_H - 3) $ul.w 1 }

    # status
    Fill-U $g 'ink' 6 41 5 5
    Fill-U $g $(if ($state.phase -eq 'idle') { 'dim' } else { 'rose' }) 7 42 3 3
    Draw-Text $g $state.status 14 40 $state.stcol 1

    # hints
    Draw-Text $g 'CLICK TOP + / BOTTOM -  SCROLL TOO' 6 50 'muted' 0.5
    Draw-Text $g 'HOLD SHIFT FOR 1 MIN STEPS' 6 55 'muted' 0.5

    # credit, right-aligned to balance the version tag up top
    $credit = 'DEVELOPED BY PJ FABIC'
    Draw-Text $g $credit ($W - 6 - (Text-Width $credit 0.5)) 61 'muted' 0.5
})

# ------------------------------------------------------------ hit testing
function Hit-Test {
    param([int]$mx, [int]$my)
    $x = $mx / $U; $y = $my / $U
    if ($y -lt $ROW_Y -or $y -gt ($ROW_Y + $ROW_H)) { return '' }
    if ($x -ge $SEG_HOUR.x -and $x -lt ($SEG_HOUR.x + $SEG_HOUR.w)) { return 'hour' }
    if ($x -ge $SEG_MIN.x  -and $x -lt ($SEG_MIN.x  + $SEG_MIN.w))  { return 'min' }
    foreach ($k in @('ampm', 's', 'h', 'act')) {
        if ($x -ge $BOX[$k].x -and $x -lt ($BOX[$k].x + $BOX[$k].w)) { return $k }
    }
    return ''
}

$canvas.Add_MouseMove({
    $hit = Hit-Test $_.X $_.Y
    if ($hit -ne $state.hover) {
        $state.hover = $hit
        switch ($hit) {
            'hour' { $state.sel = 'hour' }
            'min'  { $state.sel = 'min' }
            'ampm' { $state.sel = 'ampm' }
            's'    { $state.sel = 'mode' }
            'h'    { $state.sel = 'mode' }
        }
        $canvas.Invalidate()
    }
})

$canvas.Add_MouseLeave({
    if ($state.hover -ne '') { $state.hover = ''; $canvas.Invalidate() }
})

$canvas.Add_MouseDown({
    $canvas.Focus() | Out-Null
    $hit  = Hit-Test $_.X $_.Y
    $fine = [bool]([Windows.Forms.Control]::ModifierKeys -band [Windows.Forms.Keys]::Shift)
    $dir  = $(if (($_.Y / $U) -lt ($ROW_Y + $ROW_H / 2)) { 1 } else { -1 })
    if ($_.Button -eq [Windows.Forms.MouseButtons]::Right) { $dir = -$dir }

    switch ($hit) {
        'hour' { Disarm-Timer; Adjust-Segment 'hour' $dir }
        'min'  { Disarm-Timer; Adjust-Segment 'min' $dir $fine }
        'ampm' { Disarm-Timer; Adjust-Segment 'ampm' 1 }
        's'    { Disarm-Timer; $state.action = 'S'; $state.sel = 'mode' }
        'h'    { Disarm-Timer; $state.action = 'H'; $state.sel = 'mode' }
        'act'  { if ($state.phase -eq 'idle') { Arm-Timer } else { Disarm-Timer $true } }
    }
    $canvas.Invalidate()
})

$canvas.Add_MouseWheel({
    $dir  = $(if ($_.Delta -gt 0) { 1 } else { -1 })
    $fine = [bool]([Windows.Forms.Control]::ModifierKeys -band [Windows.Forms.Keys]::Shift)
    $seg  = switch ($state.hover) {
        'hour' { 'hour' } 'min' { 'min' } 'ampm' { 'ampm' }
        's'    { 'mode' } 'h'   { 'mode' } default { '' }
    }
    if ($seg) { Disarm-Timer; Adjust-Segment $seg $dir $fine; $canvas.Invalidate() }
})

$form.Add_KeyDown({
    $segs = @('hour', 'min', 'ampm', 'mode')
    $i = [Array]::IndexOf($segs, [string]$state.sel)
    if ($i -lt 0) { $i = 0 }
    switch ($_.KeyCode) {
        'Left'   { $state.sel = $segs[(($i - 1) + 4) % 4] }
        'Right'  { $state.sel = $segs[($i + 1) % 4] }
        'Up'     { Disarm-Timer; Adjust-Segment $state.sel 1 ([bool]$_.Shift) }
        'Down'   { Disarm-Timer; Adjust-Segment $state.sel -1 ([bool]$_.Shift) }
        'Return' { if ($state.phase -eq 'idle') { Arm-Timer } else { Disarm-Timer $true } }
        'Escape' { Disarm-Timer $true }
    }
    $canvas.Invalidate()
})

$timer.Add_Tick({ Update-Countdown })
$form.Add_Shown({ $canvas.Focus() | Out-Null })
# The countdown lives in this process, so closing the window cancels it.
# Ask first instead of silently throwing away an armed timer.
$form.Add_FormClosing({
    if ($state.phase -eq 'armed') {
        $answer = [Windows.Forms.MessageBox]::Show(
            "A timer is running ($($state.target.ToString('h:mm tt'))).`r`n" +
            "Closing this window cancels it. Close anyway?",
            'Shutdown Scheduler', 'YesNo', 'Warning')
        if ($answer -ne 'Yes') { $_.Cancel = $true; return }
    }
    $timer.Stop()
})

[void]$form.ShowDialog()
$form.Dispose()

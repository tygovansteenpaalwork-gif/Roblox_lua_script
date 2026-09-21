<#
  Takes a picture of the Terkan menu in the running Roblox window and saves it as a PNG (Windows only).

    powershell -NoProfile -File tools/screenshot.ps1 -Out assets/tabs/rage.png

  The window is put at a fixed size (1456 x 1048) and on top while it is captured, and the menu, which is centred,
  is cut out (-CX -CY -CW -CH change the crop). Switch tab first, from the executor:
      getgenv().__TerkanUniversal.Win:SelectTab("Rage")
  The 15 pictures in assets/tabs/ were made this way, one call per tab.
#>
param([string]$Out, [int]$CX = 358, [int]$CY = 244, [int]$CW = 736, [int]$CH = 586)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
}
"@
$h = [IntPtr]::Zero
for ($i = 0; $i -lt 15 -and $h -eq [IntPtr]::Zero; $i++) {
  $p = Get-Process | Where-Object { $_.ProcessName -like "Roblox*" -and $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if ($p) { $h = $p.MainWindowHandle } else { Start-Sleep -Milliseconds 400 }
}
if ($h -eq [IntPtr]::Zero) { throw "Roblox window not found" }
[W]::ShowWindow($h, 9) | Out-Null
[W]::SetForegroundWindow($h) | Out-Null
[W]::SetWindowPos($h, [IntPtr]::new(-1), 40, 0, 1456, 1048, 0) | Out-Null   # topmost while we capture
Start-Sleep -Milliseconds 900
$r = New-Object W+RECT
[W]::GetWindowRect($h, [ref]$r) | Out-Null
$w = $r.R - $r.L; $hgt = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap $w, $hgt
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size $w, $hgt))
$g.Dispose()
[W]::SetWindowPos($h, [IntPtr]::new(-2), 40, 0, 1456, 1048, 0) | Out-Null   # back to normal
"window $w x $hgt"
$crop = New-Object System.Drawing.Bitmap $CW, $CH
$cg = [System.Drawing.Graphics]::FromImage($crop)
$cg.DrawImage($bmp, (New-Object System.Drawing.Rectangle 0, 0, $CW, $CH), (New-Object System.Drawing.Rectangle $CX, $CY, $CW, $CH), [System.Drawing.GraphicsUnit]::Pixel)
$cg.Dispose()
New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
$crop.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$crop.Dispose(); $bmp.Dispose()
"$CW x $CH -> $Out"

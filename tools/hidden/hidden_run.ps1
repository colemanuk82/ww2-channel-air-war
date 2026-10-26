# Runs a program on a separate, never-shown Windows desktop so its window cannot appear or take focus.
# Usage: hidden_run.ps1 -Exe <path> -ArgLine "<args>" [-TimeoutSec 150]
param([string]$Exe, [string]$ArgLine, [int]$TimeoutSec = 150, [string]$Desk = 'ClaudeShots')
if (-not ('HD' -as [type])) {
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class HD {
  [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern IntPtr CreateDesktop(string n, IntPtr dev, IntPtr dm, int f, uint acc, IntPtr sa);
  [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr h);
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct SI { public int cb; public string r; public string desk; public string title; public int x, y, w, h, cx, cy, fill, flags; public short show, cb2; public IntPtr r2, i, o, e; }
  [StructLayout(LayoutKind.Sequential)] struct PI { public IntPtr hp, ht; public int pid, tid; }
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool CreateProcess(string app, string cmd, IntPtr pa, IntPtr ta, bool inh, uint fl, IntPtr env, string dir, ref SI si, out PI pi);
  [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint ms);
  [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr h, uint c);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  public static int Run(string desk, string cmd, string dir, uint ms) {
    IntPtr d = CreateDesktop(desk, IntPtr.Zero, IntPtr.Zero, 0, 0x10000000, IntPtr.Zero);
    if (d == IntPtr.Zero) return -2;
    SI si = new SI(); si.cb = Marshal.SizeOf(typeof(SI)); si.desk = "WinSta0\\" + desk;
    PI pi;
    if (!CreateProcess(null, cmd, IntPtr.Zero, IntPtr.Zero, false, 0x08000000, IntPtr.Zero, dir, ref si, out pi)) { CloseDesktop(d); return -3; }
    uint w = WaitForSingleObject(pi.hp, ms);
    if (w != 0) TerminateProcess(pi.hp, 1);
    CloseHandle(pi.ht); CloseHandle(pi.hp); CloseDesktop(d);
    return (int)w;
  }
}
'@
}
$r = [HD]::Run($Desk, "`"$Exe`" $ArgLine", (Split-Path $Exe), [uint32]($TimeoutSec * 1000))
"hidden_run result=$r"

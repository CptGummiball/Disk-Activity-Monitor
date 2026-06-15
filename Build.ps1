<#
.SYNOPSIS
    Kompiliert DiskMonitor.ps1 zu einer eigenstaendigen DiskMonitor.exe
.DESCRIPTION
    Nutzt den eingebauten C#-Compiler (csc.exe) aus dem .NET Framework.
    Keine externen Tools noetig - funktioniert auf jedem Windows 10/11.
.NOTES
    Ausfuehren: .\Build.ps1
    Ergebnis:   DiskMonitor.exe im selben Ordner
#>

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "  =========================================" -ForegroundColor Cyan
Write-Host "    Disk Activity Monitor - Build" -ForegroundColor Cyan
Write-Host "  =========================================" -ForegroundColor Cyan
Write-Host ""

# ── 1. Find csc.exe from .NET Framework ──
$cscPath = $null
$frameworkDirs = @(
    "$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319",
    "$env:SystemRoot\Microsoft.NET\Framework\v4.0.30319",
    "$env:SystemRoot\Microsoft.NET\Framework64\v3.5",
    "$env:SystemRoot\Microsoft.NET\Framework\v3.5"
)
foreach ($dir in $frameworkDirs) {
    $candidate = Join-Path $dir "csc.exe"
    if (Test-Path $candidate) {
        $cscPath = $candidate
        break
    }
}
if (-not $cscPath) {
    Write-Host "  [FEHLER] csc.exe nicht gefunden!" -ForegroundColor Red
    Write-Host "  .NET Framework 4.x muss installiert sein." -ForegroundColor Red
    Read-Host "  Enter zum Beenden"
    exit 1
}
Write-Host "  [OK] C#-Compiler: $cscPath" -ForegroundColor Green

# ── 2. Read the PowerShell script ──
$ps1Path = Join-Path $scriptDir "DiskMonitor.ps1"
if (-not (Test-Path $ps1Path)) {
    Write-Host "  [FEHLER] DiskMonitor.ps1 nicht gefunden!" -ForegroundColor Red
    Read-Host "  Enter zum Beenden"
    exit 1
}
$ps1Content = [IO.File]::ReadAllText($ps1Path, [Text.Encoding]::UTF8)
Write-Host "  [OK] DiskMonitor.ps1 gelesen ($([Math]::Round($ps1Content.Length / 1024, 1)) KB)" -ForegroundColor Green

# ── 3. Escape PS1 content for C# verbatim string ──
# In a C# verbatim string (@"..."), only " needs to be escaped to ""
$escapedContent = $ps1Content.Replace('"', '""')

# ── 4. Generate C# wrapper source ──
$csSource = @"
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using System.Text;

[assembly: AssemblyTitle("Disk Activity Monitor")]
[assembly: AssemblyDescription("Echtzeit-Ueberwachung der Festplattenzugriffe pro Prozess")]
[assembly: AssemblyProduct("DiskActivityMonitor")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]
[assembly: AssemblyCopyright("MIT License")]

namespace DiskActivityMonitor
{
    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            // Check if running as admin
            bool isAdmin = false;
            try
            {
                WindowsIdentity identity = WindowsIdentity.GetCurrent();
                WindowsPrincipal principal = new WindowsPrincipal(identity);
                isAdmin = principal.IsInRole(WindowsBuiltInRole.Administrator);
            }
            catch { }

            // If not admin, try to re-launch elevated
            if (!isAdmin && !HasFlag(args, "--no-elevate"))
            {
                try
                {
                    ProcessStartInfo startInfo = new ProcessStartInfo();
                    startInfo.FileName = Process.GetCurrentProcess().MainModule.FileName;
                    startInfo.Arguments = "--no-elevate";
                    startInfo.UseShellExecute = true;
                    startInfo.Verb = "runas";
                    Process.Start(startInfo);
                    return;
                }
                catch
                {
                    // User declined UAC or error - continue without admin
                }
            }

            // Extract PS1 to temp file
            string tempDir = Path.Combine(Path.GetTempPath(), "DiskActivityMonitor");
            Directory.CreateDirectory(tempDir);
            string tempPs1 = Path.Combine(tempDir, "DiskMonitor.ps1");

            try
            {
                File.WriteAllText(tempPs1, SCRIPT_CONTENT, Encoding.UTF8);
            }
            catch (Exception ex)
            {
                System.Windows.Forms.MessageBox.Show(
                    "Fehler beim Extrahieren des Scripts:\n" + ex.Message,
                    "Disk Activity Monitor - Fehler",
                    System.Windows.Forms.MessageBoxButtons.OK,
                    System.Windows.Forms.MessageBoxIcon.Error
                );
                return;
            }

            // Launch PowerShell with the script
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = "powershell.exe";
            psi.Arguments = string.Format(
                "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File \"{0}\"",
                tempPs1
            );
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;

            try
            {
                Process proc = Process.Start(psi);
                proc.WaitForExit();
            }
            catch (Exception ex)
            {
                System.Windows.Forms.MessageBox.Show(
                    "Fehler beim Starten von PowerShell:\n" + ex.Message,
                    "Disk Activity Monitor - Fehler",
                    System.Windows.Forms.MessageBoxButtons.OK,
                    System.Windows.Forms.MessageBoxIcon.Error
                );
            }
            finally
            {
                // Cleanup temp file
                try { File.Delete(tempPs1); } catch { }
                try { Directory.Delete(tempDir, false); } catch { }
            }
        }

        static bool HasFlag(string[] args, string flag)
        {
            foreach (string arg in args)
            {
                if (string.Equals(arg, flag, StringComparison.OrdinalIgnoreCase))
                    return true;
            }
            return false;
        }

        const string SCRIPT_CONTENT = @"$escapedContent";
    }
}
"@

$csPath = Join-Path $scriptDir "_build_wrapper.cs"
[IO.File]::WriteAllText($csPath, $csSource, [Text.Encoding]::UTF8)
Write-Host "  [OK] C#-Wrapper generiert" -ForegroundColor Green

# ── 5. Compile with csc.exe ──
$exePath = Join-Path $scriptDir "DiskMonitor.exe"

Write-Host "  [..] Kompiliere..." -ForegroundColor Yellow

$cscArgs = @(
    "/target:winexe",
    "/out:`"$exePath`"",
    "/reference:System.dll",
    "/reference:System.Windows.Forms.dll",
    "/optimize+",
    "/nologo",
    "/warn:0",
    "`"$csPath`""
)

$cscProcess = Start-Process -FilePath $cscPath -ArgumentList $cscArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput (Join-Path $scriptDir "_build_stdout.log") -RedirectStandardError (Join-Path $scriptDir "_build_stderr.log")

$stdout = ""
$stderr = ""
$stdoutLog = Join-Path $scriptDir "_build_stdout.log"
$stderrLog = Join-Path $scriptDir "_build_stderr.log"
if (Test-Path $stdoutLog) { $stdout = Get-Content $stdoutLog -Raw -ErrorAction SilentlyContinue }
if (Test-Path $stderrLog) { $stderr = Get-Content $stderrLog -Raw -ErrorAction SilentlyContinue }

# Cleanup temp files
Remove-Item $csPath -Force -ErrorAction SilentlyContinue
Remove-Item $stdoutLog -Force -ErrorAction SilentlyContinue
Remove-Item $stderrLog -Force -ErrorAction SilentlyContinue

if ($cscProcess.ExitCode -ne 0) {
    Write-Host "  [FEHLER] Kompilierung fehlgeschlagen!" -ForegroundColor Red
    if ($stdout) { Write-Host $stdout -ForegroundColor Red }
    if ($stderr) { Write-Host $stderr -ForegroundColor Red }
    Read-Host "  Enter zum Beenden"
    exit 1
}

if (-not (Test-Path $exePath)) {
    Write-Host "  [FEHLER] EXE wurde nicht erstellt!" -ForegroundColor Red
    Read-Host "  Enter zum Beenden"
    exit 1
}

$exeSize = [Math]::Round((Get-Item $exePath).Length / 1024, 1)
Write-Host "  [OK] Kompilierung erfolgreich!" -ForegroundColor Green
Write-Host ""
Write-Host "  =========================================" -ForegroundColor Cyan
Write-Host "    Ergebnis: DiskMonitor.exe ($exeSize KB)" -ForegroundColor White
Write-Host "  =========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Doppelklick auf DiskMonitor.exe genuegt!" -ForegroundColor Green
Write-Host ""

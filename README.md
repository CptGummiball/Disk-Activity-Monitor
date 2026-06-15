# 💽 Disk Activity Monitor

**Real-time Monitoring: Which process is accessing which storage device?**

A lightweight Windows desktop tool that shows in real-time which processes are accessing which drives – including read/write speeds, drive mapping, and a dark, professional UI.

![Windows](https://img.shields.io/badge/Windows-10%2F11-0078D6?style=flat-square&logo=windows)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE?style=flat-square&logo=powershell)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)
![Dependencies](https://img.shields.io/badge/Dependencies-Zero-brightgreen?style=flat-square)

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| **Real-time I/O-Monitoring** | Read/write speed per process via `GetProcessIoCounters` (kernel32.dll) |
| **Drive Cards** | All storage devices with capacity, usage, and I/O rate |
| **Drive Mapping** | Shows which drive an active process is utilizing |
| **Dark Theme** | Professional dark UI with color-coded values |
| **Sorting** | Click on column headers to sort the table |
| **Search & Filter** | Process search + Toggle for "active processes only" |
| **Context Menu** | Right-click → End process / Open file location |
| **Zero Dependencies** | Uses only native Windows tools (PowerShell + .NET WinForms + WMI) |
| **Auto-Elevation** | Automatically requests Admin privileges for full visibility |

## 🚀 Quickstart

### Option 1: EXE (Recommended)

> **Simply double-click `DiskMonitor.exe`** – done.

If the EXE does not exist yet, run `Build.bat` once (see below).

### Option 2: Batch File

> **Double-click `DiskMonitor.bat`** – runs the PowerShell script directly.

### Option 3: PowerShell directly

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\DiskMonitor.ps1
```

## 🔨 Build EXE

The EXE is built using the built-in .NET compiler (`csc.exe`) – **no additional tools needed**.

```
Build.bat
```

The Build script:
1. Reads `DiskMonitor.ps1`
2. Creates a C# wrapper that embeds the script
3. Compiles with `csc.exe` from the .NET Framework
4. Generates `DiskMonitor.exe` in the same folder

> **Requirement for the build:** .NET Framework 4.x (pre-installed on Windows 10/11)

## ⌨️ Keyboard Shortcuts

| Key | Action |
|-------|--------|
| `F5` | Refresh |
| `Ctrl+F` | Focus search |
| `Pause` | Pause / Resume |
| `Esc` | Quit |

## 🏗️ Project Structure

```
📁 DiskActivityMonitor/
├── DiskMonitor.exe      ← Standalone EXE (after Build)
├── DiskMonitor.ps1      ← Main application (Source code)
├── DiskMonitor.bat      ← Alternative launcher (without Build)
├── Build.ps1            ← Build script (PS1 → EXE)
├── Build.bat            ← Start build (Double-click)
└── README.md            ← This file
```

## 🔧 Technical Details

### Architecture

- **GUI:** .NET WinForms via PowerShell (no external UI frameworks)
- **I/O Data:** `GetProcessIoCounters` via P/Invoke (kernel32.dll) – direct Windows API
- **Drives:** WMI (`Win32_LogicalDisk` + `Win32_PerfFormattedData_PerfDisk_LogicalDisk`)
- **Process Mapping:** Executable path analysis (`MainModule.FileName`)
- **EXE Wrapper:** C# Stub compiled with `csc.exe`, embeds PS1 script

### Color Coding

| Color | Meaning |
|-------|-----------|
| 🔵 Blue | Read speed |
| 🟠 Orange | Write speed |
| 🟢 Green | Active process (●) |
| 🔷 Cyan | Drive mapping |

### Refresh Interval

The tool updates every **2 seconds**. Drive information is reloaded every **10 seconds**.

## 📋 System Requirements

- **Windows 10** or **Windows 11**
- **PowerShell 5.1+** (pre-installed)
- **.NET Framework 4.x** (pre-installed)
- **Administrator rights** recommended (for full process visibility)

> The tool also runs without Admin rights, but it may not be able to monitor all processes.

## 📄 License

MIT License – free to use, modify, and distribute.

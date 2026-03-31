# ScreenConnect GPO MSI Finder

Find GPOs that deploy ConnectWise ScreenConnect/Control and scripts that may install CW Automate RMM or ScreenConnect. **Run remotely** from the ConnectWise ScreenConnect Commands window—no install, no files to copy. Paste a one-liner, download and run.

---

## Run Remotely (Download & Execute)

Connect to a session in ScreenConnect, open the **Commands** window, and paste one of these:

### Standard (recommended — download then run)

`irm … | iex` runs **whatever** the URL returns. If a **proxy**, **TLS inspection** (SSL bump), or **web filter / secure web gateway** returns an **HTML** block page, login, or “deny” page instead of the raw `.ps1`, `iex` parses that text and you get errors about `&`, `redirect`, base64, etc. Prefer saving the file first.

The download guard looks for **HTML document** markers (`<!DOCTYPE`, `<html`, `<head`) on the first non-blank line—not merely any `<`, because this script legitimately starts with `<#` (a PowerShell comment block).

**From cmd.exe or “Run as administrator”:**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Join-Path $env:TEMP 'Find-ScreenConnectGPO.ps1'; Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/monobrau/screenconnect-gpo-msi-finder/main/Find-ScreenConnectGPO.ps1' -OutFile $p -UseBasicParsing; $f=@(Get-Content $p -TotalCount 15 | Where-Object { $_.Trim() })[0]; if ($f -match '^\s*(<!DOCTYPE|<html\b|<head\b)') { Write-Error ('Download looks like HTML, not the script (proxy, TLS inspection, or web filter). Path: ' + $p); exit 1 }; & $p"
```

**Already at a `PS>` prompt:**

```powershell
$p = Join-Path $env:TEMP 'Find-ScreenConnectGPO.ps1'
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/monobrau/screenconnect-gpo-msi-finder/main/Find-ScreenConnectGPO.ps1' -OutFile $p -UseBasicParsing
$f = @(Get-Content $p -TotalCount 15 | Where-Object { $_.Trim() })[0]
if ($f -match '^\s*(<!DOCTYPE|<html\b|<head\b)') { throw "Got HTML instead of script. Open in Notepad: $p" }
& $p
```

### Fallback mirror (if the guard says the download is HTML)

That message means the URL returned a web page (proxy, TLS inspection, or **web filter** category rules), not the script. Try the same one-liner with **jsDelivr** instead—same file, different host (sometimes in another URL category than `raw.githubusercontent.com`):

**From cmd.exe:**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Join-Path $env:TEMP 'Find-ScreenConnectGPO.ps1'; Invoke-WebRequest -Uri 'https://cdn.jsdelivr.net/gh/monobrau/screenconnect-gpo-msi-finder@main/Find-ScreenConnectGPO.ps1' -OutFile $p -UseBasicParsing; $f=@(Get-Content $p -TotalCount 15 | Where-Object { $_.Trim() })[0]; if ($f -match '^\s*(<!DOCTYPE|<html\b|<head\b)') { Write-Error ('Download looks like HTML, not the script. Path: ' + $p); exit 1 }; & $p"
```

**Already at a `PS>` prompt:** use the same `-Uri` as above in `Invoke-WebRequest`. If both hosts return HTML, copy `Find-ScreenConnectGPO.ps1` from this repo over RDP/USB/internal share, or ask IT to allow (or recategorize) unmodified HTTPS to `raw.githubusercontent.com` and `cdn.jsdelivr.net`—filters often tag GitHub/CDN as *Software/Development* or *Shareware* and substitute a block page.

### TLS 1.2 workaround (older hosts / “Could not create SSL/TLS secure channel”)

Run this **once in the same session** before the download line, or prepend it inside the `-Command` string (after `$p=Join-Path …`):

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
```

### `irm | iex` (only if you truly get raw script text)

```powershell
irm https://raw.githubusercontent.com/monobrau/screenconnect-gpo-msi-finder/main/Find-ScreenConnectGPO.ps1 | iex
```

Skip this in locked-down networks; use the download-then-run blocks above.

### With parameters (specify DC and domain)

Use **double-quoted** path assignment or `Join-Path` so `$env:TEMP` expands. (A line like `$s='$env:TEMP\...'` keeps `$env:TEMP` literal and makes `-OutFile` fail with “drive '$env' does not exist”.)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=Join-Path $env:TEMP 'Find-ScreenConnectGPO.ps1'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/monobrau/screenconnect-gpo-msi-finder/main/Find-ScreenConnectGPO.ps1' -OutFile $s -UseBasicParsing; $f=@(Get-Content $s -TotalCount 15 | Where-Object { $_.Trim() })[0]; if ($f -match '^\s*(<!DOCTYPE|<html\b|<head\b)') { Write-Error ('Download looks like HTML, not the script (proxy, TLS inspection, or web filter). Path: ' + $s); exit 1 }; & $s -DomainController 'DC01.corp.contoso.com' -Domain 'corp.contoso.com'"
```

If that fails the HTML check, use the same command but replace the `-Uri` value with `https://cdn.jsdelivr.net/gh/monobrau/screenconnect-gpo-msi-finder@main/Find-ScreenConnectGPO.ps1`.

---

## Troubleshooting

**`irm ... | iex` errors about `&`, `redirect`, base64, or “string is missing the terminator”**  
The URL response is **not** the script—it is usually **HTML** (GitHub’s page, a **web filter** block, a proxy challenge, or TLS inspection). Use the **download then run** commands above.

**The guard says the download “looks like HTML”**  
The first non-blank line matched a typical HTML document start. If you fixed an older README one-liner that treated any leading `<` as HTML, note that **this script starts with `<#`**—that is valid PowerShell, not a page. Use the current guards above. If the file in Notepad really is HTML, try **jsDelivr** or an internal copy. **Web filters** often block or replace GitHub and CDN URLs by category; IT may need an exception for `raw.githubusercontent.com` and `cdn.jsdelivr.net`, or you can host the `.ps1` on an internal file share and run it with `& \\server\share\Find-ScreenConnectGPO.ps1`.

**“Could not find drive '$env'” on `-OutFile`**  
The temp path was assigned inside **single quotes**. Use `Join-Path $env:TEMP 'Find-ScreenConnectGPO.ps1'` or `"$env:TEMP\Find-ScreenConnectGPO.ps1"` (double quotes) when setting `$s`.

---

## What You Get

**GPO Software Installation (MSI):**
- **GPO Name** – Which GPO deploys ScreenConnect/Control  
- **App Name** – Deployed application display name  
- **MSIPath** – Full UNC path to the MSI (e.g. `\\server\share\path\file.msi`)  
- **LocalPath** – Physical path on the file server (e.g. `D:\Shares\path\file.msi`); N/A if server is unreachable or account lacks admin rights  
- **Share** – `\\server\share` where the MSI is stored  
- **Created / Modified** – MSI file dates (N/A if share inaccessible)

**GPO Scripts (Logon, Logoff, Startup, Shutdown):**
- Scripts in any GPO that reference CW Automate RMM, ScreenConnect, or related install commands—often used to "hide" deployments outside Software Installation.

---

## Requirements

- PowerShell 5.1+ (Windows PowerShell)
- **RSAT**: GroupPolicy and ActiveDirectory modules  
  - Windows Server: `Install-WindowsFeature RSAT-AD-PowerShell, RSAT-GP`  
  - Windows 10/11: Settings → Apps → Optional Features → RSAT
- Domain-joined machine (or use `-DomainController` and `-Domain`)
- Read access to GPOs (typically Domain Users or higher)

---

## Run from Local Script (Optional)

If you've cloned or copied the script locally:

```powershell
& "C:\path\to\Find-ScreenConnectGPO.ps1"
```

Parameters: `-DomainController`, `-Domain`

---

## How It Works

1. **Software Installation** – Queries the AD Class Store for each GPO’s packages; matches on GPO name, app name, or MSI path; extracts share and MSI file dates.
2. **Scripts** – Scans GPO Logon, Logoff, Startup, and Shutdown scripts (.bat, .cmd, .ps1, .vbs) for references to screenconnect, connectwise, automate, labtech, msiexec, etc.

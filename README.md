# ScreenConnect GPO MSI Finder

Find GPOs that deploy ConnectWise ScreenConnect/Control and scripts that may install CW Automate RMM or ScreenConnect. **Run remotely** from the ConnectWise ScreenConnect Commands window—no install, no files to copy. Paste a one-liner, download and run.

---

## Run Remotely (Download & Execute)

Connect to a session in ScreenConnect, open the **Commands** window, and paste one of these:

### Standard (recommended — download then run)

`irm … | iex` runs **whatever** the URL returns. If a proxy or SSL inspector returns an **HTML** page instead of the raw `.ps1`, `iex` parses that text and you get errors about `&`, `redirect`, base64, etc. Prefer saving the file first:

**From cmd.exe or “Run as administrator”:**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Join-Path $env:TEMP 'Find-ScreenConnectGPO.ps1'; Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/monobrau/screenconnect-gpo-msi-finder/main/Find-ScreenConnectGPO.ps1' -OutFile $p -UseBasicParsing; if ((Get-Content $p -TotalCount 1) -match '^\s*<') { Write-Error ('Download is HTML, not the script (check proxy / SSL inspection). Path: ' + $p); exit 1 }; & $p"
```

**Already at a `PS>` prompt:**

```powershell
$p = Join-Path $env:TEMP 'Find-ScreenConnectGPO.ps1'
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/monobrau/screenconnect-gpo-msi-finder/main/Find-ScreenConnectGPO.ps1' -OutFile $p -UseBasicParsing
if ((Get-Content $p -TotalCount 1) -match '^\s*<') { throw "Got HTML instead of script. Open in Notepad: $p" }
& $p
```

### Fallback mirror (if the guard says the download is HTML)

That message means the URL returned a web page (proxy, SSL inspection, or filter), not the script. Try the same one-liner with **jsDelivr** instead—same file, different host (sometimes allowed when `raw.githubusercontent.com` is not):

**From cmd.exe:**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Join-Path $env:TEMP 'Find-ScreenConnectGPO.ps1'; Invoke-WebRequest -Uri 'https://cdn.jsdelivr.net/gh/monobrau/screenconnect-gpo-msi-finder@main/Find-ScreenConnectGPO.ps1' -OutFile $p -UseBasicParsing; if ((Get-Content $p -TotalCount 1) -match '^\s*<') { Write-Error ('Download is HTML, not the script. Path: ' + $p); exit 1 }; & $p"
```

**Already at a `PS>` prompt:** use the same `-Uri` as above in `Invoke-WebRequest`. If both hosts return HTML, copy `Find-ScreenConnectGPO.ps1` from this repo over RDP/USB/internal share, or ask IT to allow unmodified HTTPS to `raw.githubusercontent.com` or `cdn.jsdelivr.net` for that use case.

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
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=Join-Path $env:TEMP 'Find-ScreenConnectGPO.ps1'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/monobrau/screenconnect-gpo-msi-finder/main/Find-ScreenConnectGPO.ps1' -OutFile $s -UseBasicParsing; if ((Get-Content $s -TotalCount 1) -match '^\s*<') { Write-Error ('Download is HTML, not the script (check proxy / SSL inspection). Path: ' + $s); exit 1 }; & $s -DomainController 'DC01.corp.contoso.com' -Domain 'corp.contoso.com'"
```

If that fails the HTML check, use the same command but replace the `-Uri` value with `https://cdn.jsdelivr.net/gh/monobrau/screenconnect-gpo-msi-finder@main/Find-ScreenConnectGPO.ps1`.

---

## Troubleshooting

**`irm ... | iex` errors about `&`, `redirect`, base64, or “string is missing the terminator”**  
The URL response is **not** the script—it is usually **HTML** (GitHub’s page, a proxy block, or an SSL inspection portal). Use the **download then run** commands above.

**The guard says “Download is HTML”**  
Your network replaced the file with a web page. Try the **Fallback mirror (jsDelivr)** section above, or copy the script from the repo by another path; IT may need to stop SSL-bumping or allowlist `raw.githubusercontent.com` / `cdn.jsdelivr.net` for script text.

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

# ScreenConnect GPO MSI Finder

Find GPOs that deploy ConnectWise ScreenConnect/Control and scripts that may install CW Automate RMM or ScreenConnect. **Run remotely** from the ConnectWise ScreenConnect Commands window—no install, no files to copy. Paste a one-liner, download and run.

---

## Run Remotely (Download & Execute)

Connect to a session in ScreenConnect, open the **Commands** window, and paste one of these:

### Standard (most environments)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/monobrau/screenconnect-gpo-msi-finder/main/Find-ScreenConnectGPO.ps1 | iex"
```

### TLS 1.2 workaround (older DCs / "Could not create SSL/TLS secure channel")

Use this if the standard command fails with an SSL/TLS error (common on older Windows Server / DCs):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; irm https://raw.githubusercontent.com/monobrau/screenconnect-gpo-msi-finder/main/Find-ScreenConnectGPO.ps1 | iex"
```

### Shorter form (when Commands window is already PowerShell)

```powershell
irm https://raw.githubusercontent.com/monobrau/screenconnect-gpo-msi-finder/main/Find-ScreenConnectGPO.ps1 | iex
```

### With parameters (specify DC and domain)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s='$env:TEMP\Find-ScreenConnectGPO.ps1'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; irm https://raw.githubusercontent.com/monobrau/screenconnect-gpo-msi-finder/main/Find-ScreenConnectGPO.ps1 -OutFile $s; & $s -DomainController DC01.corp.contoso.com -Domain corp.contoso.com"
```

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

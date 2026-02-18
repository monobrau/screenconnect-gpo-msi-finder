# ScreenConnect GPO MSI Finder

Find GPOs that deploy ConnectWise ScreenConnect/Control and the share where the MSI is stored. **Run remotely** from the ConnectWise ScreenConnect Commands window—no install, no files to copy. Paste a one-liner, download and run.

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

- **GPO Name** – Which GPO deploys ScreenConnect/Control  
- **App Name** – Deployed application display name  
- **MSI Path** – Full UNC path to the MSI  
- **Share** – `\\server\share` where the MSI is stored  
- **Created / Modified** – MSI file dates (N/A if share inaccessible)

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

1. Queries the AD Class Store for each GPO’s Software Installation packages.
2. Matches on GPO name, app name, or MSI path (screenconnect, connectwise, SC, control, etc.).
3. Extracts the share from each UNC path and fetches MSI file dates when accessible.

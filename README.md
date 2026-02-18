# ScreenConnect GPO MSI Finder

A PowerShell script that finds Group Policy Objects (GPOs) that deploy ConnectWise ScreenConnect/Control and returns the share where the MSI file is stored. Designed to run from the ConnectWise ScreenConnect Commands window.

## Purpose

When managing customer environments via ScreenConnect, you may need to:
- Identify which GPO deploys ConnectWise ScreenConnect/Control
- Find the UNC share path where the deployment MSI is stored
- Audit or update deployments across multiple GPOs

This script queries the Domain Controller directly to answer those questions.

## Requirements

- **PowerShell 5.1+** (Windows PowerShell)
- **RSAT**: GroupPolicy and ActiveDirectory modules
  - `Install-WindowsFeature RSAT-AD-PowerShell, RSAT-GP` (Windows Server)
  - Or enable via Settings → Apps → Optional Features → RSAT (Windows 10/11)
- **Domain-joined machine** (when auto-discovering DC), or specify `-DomainController` explicitly
- **Permissions**: Read access to GPOs and AD (typically Domain Users or higher)

## Usage

### Run from ScreenConnect Commands (Download & Execute)

Paste this into the ScreenConnect **Commands** window to download and run the script in one step:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/monobrau/screenconnect-gpo-msi-finder/main/Find-ScreenConnectGPO.ps1 | iex"
```

If the Commands window is already PowerShell, use the shorter form:

```powershell
irm https://raw.githubusercontent.com/monobrau/screenconnect-gpo-msi-finder/main/Find-ScreenConnectGPO.ps1 | iex
```

With parameters (e.g., specify DC)—download to temp, then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s='$env:TEMP\Find-ScreenConnectGPO.ps1'; irm https://raw.githubusercontent.com/monobrau/screenconnect-gpo-msi-finder/main/Find-ScreenConnectGPO.ps1 -OutFile $s; & $s -DomainController DC01.corp.contoso.com -Domain corp.contoso.com"
```

### Run from Local Script File

```powershell
& "C:\path\to\Find-ScreenConnectGPO.ps1"
```

### Parameters

| Parameter           | Required | Description                                                                 |
|--------------------|----------|-----------------------------------------------------------------------------|
| `-DomainController`| No       | Domain Controller hostname/FQDN to query. If omitted, the script discovers it. |
| `-Domain`          | No       | Fully qualified domain name. If omitted, uses the current domain.           |

### Examples

```powershell
# Auto-discover DC (run on domain-joined machine)
.\Find-ScreenConnectGPO.ps1

# Specify DC and domain (e.g. when running from different context)
.\Find-ScreenConnectGPO.ps1 -DomainController DC01.corp.contoso.com -Domain corp.contoso.com
```

## Output

The script outputs:
- **GPO Name** – Name of the GPO deploying ScreenConnect/Control
- **App Name** – Display name of the deployed application
- **MSI Path** – Full UNC path to the MSI file
- **Share** – The `\\server\share` portion where the MSI is stored

Example:
```
Found 2 deployment(s):

GPOName     AppName                    MSIPath                                    Share
-------     -------                    ------                                    -----
Deploy-CW   ConnectWise Control        \\fileserver\software\ScreenConnect\...   \\fileserver\software
CW-Agent    ScreenConnect Agent        \\nas\deploy\cw\ControlAgent.msi           \\nas\deploy

--- Summary: GPO and Share ---
  GPO: Deploy-CW  |  Share: \\fileserver\software
  GPO: CW-Agent   |  Share: \\nas\deploy
```

## How It Works

1. **Class Store query** – Queries the AD Class Store (`CN=Packages`) for each GPO’s Software Installation policies and extracts `msiFileList` and `displayName`.
2. **Pattern matching** – Filters for names/paths containing: `screenconnect`, `connectwise`, `connect wise`, `control`, etc.
3. **Share extraction** – Derives the `\\server\share` from each MSI UNC path.
4. **Fallback** – If no matches are found, parses GPO XML reports for software installation references.

## License

Use freely for internal and customer support purposes.

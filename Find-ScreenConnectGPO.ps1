<#
.SYNOPSIS
    Finds GPOs that deploy ConnectWise ScreenConnect/Control and returns the share where the MSI is stored.

.DESCRIPTION
    Designed to run from ConnectWise ScreenConnect Commands window. Queries the Domain Controller
    directly to find: (1) GPO Software Installation deployments and the MSI share path,
    (2) Logon/Logoff/Startup/Shutdown scripts that reference CW Automate RMM or ScreenConnect.

.PARAMETER DomainController
    Optional. Specifies the Domain Controller to query. If omitted, discovers the DC automatically
    (requires domain-joined machine).

.PARAMETER Domain
    Optional. Fully qualified domain name. If omitted, uses current domain.

.EXAMPLE
    .\Find-ScreenConnectGPO.ps1

.EXAMPLE
    .\Find-ScreenConnectGPO.ps1 -DomainController DC01.corp.contoso.com -Domain corp.contoso.com

.NOTES
    Requires: GroupPolicy and ActiveDirectory PowerShell modules (RSAT)
    Run from: ConnectWise ScreenConnect Commands window (PowerShell)
    Typically run on the remote session (domain-joined machine) or with -DomainController specified
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$DomainController,

    [Parameter(Mandatory = $false)]
    [string]$Domain
)

# Keywords to match ConnectWise ScreenConnect/Control - in GPO name, app name, or MSI path
$SearchPatterns = @('screenconnect', 'screen connect', 'connectwise', 'connect wise', 'control\.msi', '\bsc\b')
# Keywords for script content - CW Automate RMM, ScreenConnect, installations
$ScriptSearchPatterns = @('screenconnect', 'screen connect', 'connectwise', 'connect wise', 'automate', 'labtech', 'ltagent', 'rrc\.remotesupport', 'remote support', 'msiexec', '\.msi', '\bsc\b')

function Test-IsMatch {
    param([string]$GpoName, [string]$Name, [string]$Path)
    $combined = "$GpoName $Name $Path".ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($combined)) { return $false }
    foreach ($pattern in $SearchPatterns) {
        $regex = if ($pattern -match '\\[a-z]') { $pattern } else { [regex]::Escape($pattern) }
        if ($combined -match $regex) { return $true }
    }
    return $false
}

function Normalize-MsiPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    # GPO/AD sometimes stores paths with prefix like "0:" or "1:" (deployment type flag) - e.g. "0:\server\share\file.msi" -> "\\server\share\file.msi"
    if ($Path -match '^\d+:(.+)$') {
        $rest = $matches[1].TrimStart('\')
        return "\\$rest"
    }
    return $Path
}

function Get-ShareFromPath {
    param([string]$UncPath)
    if ([string]::IsNullOrWhiteSpace($UncPath)) { return $null }
    $UncPath = Normalize-MsiPath -Path $UncPath
    # UNC format: \\server\share\path\to\file.msi - extract \\server\share
    $parts = $UncPath.TrimStart('\') -split '\\+'
    if ($parts.Count -ge 2) {
        return "\\$($parts[0])\$($parts[1])"
    }
    return $null
}

$script:LocalPathCache = @{}
function Get-LocalPathFromUnc {
    param([string]$UncPath)
    if ([string]::IsNullOrWhiteSpace($UncPath)) { return 'N/A' }
    $UncPath = Normalize-MsiPath -Path $UncPath
    $parts = $UncPath.TrimStart('\') -split '\\+'
    if ($parts.Count -lt 2) { return 'N/A' }
    $server = $parts[0]
    $shareName = $parts[1]
    $subPath = $parts[2..($parts.Count - 1)] -join '\'
    $cacheKey = "\\$server\$shareName"
    if (-not $script:LocalPathCache.ContainsKey($cacheKey)) {
        $localRoot = 'N/A'
        try {
            $share = Get-SmbShare -CimSession (New-CimSession -ComputerName $server -ErrorAction Stop) -ErrorAction Stop | Where-Object { $_.Name -eq $shareName }
            if ($share) { $localRoot = $share.Path.TrimEnd('\') }
        }
        catch {
            try {
                $share = Get-WmiObject Win32_Share -ComputerName $server -Filter "Name='$shareName'" -ErrorAction Stop
                if ($share) { $localRoot = $share.Path.TrimEnd('\') }
            }
            catch { }
        }
        $script:LocalPathCache[$cacheKey] = $localRoot
    }
    $localRoot = $script:LocalPathCache[$cacheKey]
    if ($localRoot -eq 'N/A') { return 'N/A' }
    if ([string]::IsNullOrWhiteSpace($subPath)) { return $localRoot }
    return Join-Path $localRoot $subPath
}

function Get-MsiFileDates {
    param([string]$UncPath)
    if ([string]::IsNullOrWhiteSpace($UncPath)) { return @{ Created = 'N/A'; Modified = 'N/A' } }
    $UncPath = Normalize-MsiPath -Path $UncPath
    try {
        $item = Get-Item -LiteralPath $UncPath -ErrorAction Stop
        return @{ Created = $item.CreationTime.ToString('yyyy-MM-dd HH:mm'); Modified = $item.LastWriteTime.ToString('yyyy-MM-dd HH:mm') }
    }
    catch {
        return @{ Created = 'N/A'; Modified = 'N/A' }
    }
}

function Test-ScriptContentMatch {
    param([string]$Content)
    if ([string]::IsNullOrWhiteSpace($Content)) { return $false }
    $lower = $Content.ToLowerInvariant()
    foreach ($pattern in $ScriptSearchPatterns) {
        $regex = if ($pattern -match '\\[a-z]') { $pattern } else { [regex]::Escape($pattern) }
        if ($lower -match $regex) { return $true }
    }
    return $false
}

function Get-GpoScriptFindings {
    param([string]$DC, [string]$Domain, [array]$Gpos)
    $sysvolRoot = "\\$DC\SYSVOL\$Domain\Policies"
    $scriptTypes = @(
        @{ Name = 'Logon';   Path = 'User\Scripts\Logon' }
        @{ Name = 'Logoff';  Path = 'User\Scripts\Logoff' }
        @{ Name = 'Startup'; Path = 'Machine\Scripts\Startup' }
        @{ Name = 'Shutdown'; Path = 'Machine\Scripts\Shutdown' }
    )
    $scriptExts = @('.bat', '.cmd', '.ps1', '.vbs')
    $findings = @()
    foreach ($gpo in $Gpos) {
        $gpoPath = Join-Path $sysvolRoot $gpo.Id.Guid
        if (-not (Test-Path $gpoPath)) { continue }
        foreach ($st in $scriptTypes) {
            $scriptDir = Join-Path $gpoPath $st.Path
            if (-not (Test-Path $scriptDir)) { continue }
            try {
                $files = Get-ChildItem -Path $scriptDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in $scriptExts }
                foreach ($f in $files) {
                    try {
                        $content = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop
                        if (Test-ScriptContentMatch -Content $content) {
                            $findings += [PSCustomObject]@{
                                GPOName   = $gpo.DisplayName
                                ScriptType = $st.Name
                                ScriptPath = $f.FullName
                                ScriptName = $f.Name
                            }
                        }
                    }
                    catch { }
                }
            }
            catch { }
        }
    }
    return $findings
}

try {
    # Ensure required modules are loaded
    $required = @('GroupPolicy', 'ActiveDirectory')
    foreach ($mod in $required) {
        if (-not (Get-Module -ListAvailable -Name $mod)) {
            Write-Output "ERROR: Required module '$mod' not found. Install RSAT: Install-WindowsFeature RSAT-AD-PowerShell, RSAT-GP."
            exit 1
        }
        Import-Module $mod -ErrorAction Stop
    }

    # Resolve Domain Controller
    if (-not $DomainController) {
        $dc = Get-ADDomainController -Discover -ErrorAction Stop
        $DomainController = $dc.HostName
    }
    if (-not $Domain) {
        $dom = Get-ADDomain -Server $DomainController -ErrorAction Stop
        $Domain = $dom.DNSRoot
    }

    Write-Output "Querying Domain Controller: $DomainController"
    Write-Output "Domain: $Domain"
    Write-Output ""

    $results = @()
    $dn = (Get-ADDomain -Server $DomainController).DistinguishedName
    $gpos = Get-GPO -All -Domain $Domain -Server $DomainController -ErrorAction Stop

    foreach ($gpo in $gpos) {
        try {
            $searchBase = "CN=Packages,CN=Class Store,CN=Machine,CN={$($gpo.Id.Guid)},CN=Policies,CN=System,$dn"
            $packages = Get-ADObject -Filter "Name -ne 'Packages'" -Server $DomainController -SearchBase $searchBase `
                -SearchScope Subtree -Properties msiFileList, displayName -ErrorAction SilentlyContinue

            if ($packages) {
                foreach ($pkg in $packages) {
                    $name = $pkg.displayName
                    $paths = @($pkg.msiFileList)
                    if (-not $paths -or $paths.Count -eq 0) { continue }

                    foreach ($path in $paths) {
                        if ([string]::IsNullOrWhiteSpace($path) -or -not ($path -match '\.(msi|mst)$')) { continue }
                        if (Test-IsMatch -GpoName $gpo.DisplayName -Name $name -Path $path) {
                            $path = Normalize-MsiPath -Path $path
                            $share = Get-ShareFromPath -UncPath $path
                            $dates = Get-MsiFileDates -UncPath $path
                            $localPath = Get-LocalPathFromUnc -UncPath $path
                            $results += [PSCustomObject]@{
                                GPOName     = $gpo.DisplayName
                                GPOGuid     = $gpo.Id.Guid
                                AppName     = $name
                                MSIPath     = $path
                                LocalPath   = $localPath
                                Share       = $share
                                Created     = $dates.Created
                                Modified    = $dates.Modified
                                DomainController = $DomainController
                            }
                        }
                    }
                }
            }
        }
        catch {
            # GPO may have no software installation - skip silently
        }
    }

    # Fallback: parse GPO reports for software installation (catches cases Class Store might miss)
    if ($results.Count -eq 0) {
        Write-Output "No matches from Class Store. Checking GPO reports..."
        foreach ($gpo in $gpos) {
            try {
                $report = Get-GPOReport -Guid $gpo.Id -ReportType Xml -Domain $Domain -Server $DomainController -ErrorAction Stop
                # Search raw report for UNC paths to .msi files containing our keywords
                $uncPaths = [regex]::Matches($report, '\\\\[^\s"''<>]+\.msi')
                foreach ($m in $uncPaths) {
                    $path = $m.Value
                    if (Test-IsMatch -GpoName $gpo.DisplayName -Name $path -Path $path) {
                        $path = Normalize-MsiPath -Path $path
                        $share = Get-ShareFromPath -UncPath $path
                        $dates = Get-MsiFileDates -UncPath $path
                        $localPath = Get-LocalPathFromUnc -UncPath $path
                        $results += [PSCustomObject]@{
                            GPOName     = $gpo.DisplayName
                            GPOGuid     = $gpo.Id.Guid
                            AppName     = 'Unknown'
                            MSIPath     = $path
                            LocalPath   = $localPath
                            Share       = $share
                            Created     = $dates.Created
                            Modified    = $dates.Modified
                            DomainController = $DomainController
                        }
                    }
                }
            }
            catch { }
        }
    }

    # Search GPO scripts (Logon, Logoff, Startup, Shutdown) for CW Automate / ScreenConnect
    Write-Output "Searching GPO scripts (Logon, Logoff, Startup, Shutdown)..."
    $scriptFindings = Get-GpoScriptFindings -DC $DomainController -Domain $Domain -Gpos $gpos

    # Output MSI deployment results
    if ($results.Count -gt 0) {
        Write-Output ""
        Write-Output "=== GPO SOFTWARE INSTALLATION (MSI) ==="
        Write-Output "Found $($results.Count) deployment(s):"
        Write-Output ""
        $results | Select-Object GPOName, AppName, MSIPath, LocalPath, Share, Created, Modified | Format-List | Out-String -Width 200 | Write-Output
        Write-Output "--- Summary: GPO and Share ---"
        $results | Select-Object GPOName, Share -Unique | ForEach-Object {
            Write-Output "  GPO: $($_.GPOName)  |  Share: $($_.Share)"
        }
    }
    else {
        Write-Output "No GPOs found that deploy ConnectWise ScreenConnect/Control via Software Installation."
    }

    # Output script findings
    if ($scriptFindings.Count -gt 0) {
        Write-Output ""
        Write-Output "=== GPO SCRIPTS (possible CW Automate/ScreenConnect install) ==="
        Write-Output "Found $($scriptFindings.Count) script(s) that may reference CW Automate RMM or ScreenConnect:"
        Write-Output ""
        $scriptFindings | Select-Object GPOName, ScriptType, ScriptName, ScriptPath | Format-List | Out-String -Width 200 | Write-Output
    }
    else {
        Write-Output "No logon/logoff/startup/shutdown scripts found referencing CW Automate or ScreenConnect."
    }

    if ($results.Count -eq 0 -and $scriptFindings.Count -eq 0) {
        Write-Output ""
        Write-Output "No matches found."
    }
}
catch {
    Write-Output "ERROR: $_"
    Write-Error "Error: $_"
    exit 1
}

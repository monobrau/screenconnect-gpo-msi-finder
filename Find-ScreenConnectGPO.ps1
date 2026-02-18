<#
.SYNOPSIS
    Finds GPOs that deploy ConnectWise ScreenConnect/Control and returns the share where the MSI is stored.

.DESCRIPTION
    Designed to run from ConnectWise ScreenConnect Commands window. Queries the Domain Controller
    directly to find any Group Policy that deploys ConnectWise ScreenConnect or Control via
    Software Installation (Assigned/Published). Returns the GPO name and the UNC share path
    where the MSI file is stored.

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
                            $results += [PSCustomObject]@{
                                GPOName     = $gpo.DisplayName
                                GPOGuid     = $gpo.Id.Guid
                                AppName     = $name
                                MSIPath     = $path
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
                        $results += [PSCustomObject]@{
                            GPOName     = $gpo.DisplayName
                            GPOGuid     = $gpo.Id.Guid
                            AppName     = 'Unknown'
                            MSIPath     = $path
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

    if ($results.Count -eq 0) {
        Write-Output "No GPOs found that deploy ConnectWise ScreenConnect/Control."
        exit 0
    }

    Write-Output "Found $($results.Count) deployment(s):"
    Write-Output ""
    $results | Select-Object GPOName, AppName, MSIPath, Share, Created, Modified | Format-List | Out-String -Width 200 | Write-Output
    Write-Output ""
    Write-Output "--- Summary: GPO and Share ---"
    $results | Select-Object GPOName, Share -Unique | ForEach-Object {
        Write-Output "  GPO: $($_.GPOName)  |  Share: $($_.Share)"
    }
}
catch {
    Write-Output "ERROR: $_"
    Write-Error "Error: $_"
    exit 1
}

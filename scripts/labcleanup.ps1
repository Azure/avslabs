# labcleanup.ps1
# Purpose: Remove resources created by labdeploy.ps1 for a given group & lab number.
# Idempotent: Safe to run multiple times; it only removes existing matching objects.
# Requires: PowerShell 7+, VMware PowerCLI modules (VCF.PowerCLI), same credentials / AVSInfo structure as deployment.

param (
    [Parameter(Mandatory)][ValidateRange(1,50)][Alias('GroupNumber')][int]$group,
    [Parameter(Mandatory)][ValidateRange(1,50)][Alias('LabNumber')][int]$lab,
    [Parameter()][Alias('IsAutomated')][switch]$automated = $false,
    [Parameter()][Alias('Credentials')][hashtable]$AVSInfo,
    [Parameter()][switch]$WhatIf,
    [Parameter()][switch]$Force
)

$ErrorActionPreference = 'Stop'
$timeStamp = (Get-Date -Format 'MM-dd-yyyy_hh.mm.ss')
$logFile = "nested-labcleanup-${group}-${lab}-${timeStamp}.log"
function Write-Log {
    param([Parameter(Mandatory)][string]$Message,[ValidateSet('Green','Yellow','Red','White','Cyan','Magenta')]$Color='Green')
    $ts = Get-Date -Format 'MM-dd-yyyy_hh:mm:ss'
    Write-Host -NoNewline -ForegroundColor White "[$ts]"
    Write-Host -ForegroundColor $Color " $Message"
    "[$ts] $Message" | Out-File -FilePath $logFile -Append -Encoding utf8
}

Write-Log "Starting cleanup process for Group=$group Lab=$lab" 'Cyan'

# Acquire configuration (mirrors labdeploy.ps1 logic)
if(!$AVSInfo -or $AVSInfo.Count -eq 0){
    Write-Log 'Reading nestedlabs.yml for credentials' 'White'
    Import-Module powershell-yaml -ErrorAction Stop
    $config = (Get-Content -Raw 'nestedlabs.yml' | ConvertFrom-Yaml)
} else { $config = $AVSInfo }

$VIServer = $config.AVSvCenter.IP
$VIUsername = $config.AVSvCenter.Username
$VIPassword = $config.AVSvCenter.Password
$nsxtHost  = $config.AVSNSXT.IP
$nsxtUser  = $config.AVSNSXT.Username
$nsxtPass  = $config.AVSNSXT.Password

# Reconstruct naming used in deployment
$groupNumber = $group
$labNumber   = $lab
$VMNetwork = "Group-${groupNumber}-${labNumber}-NestedLab"   # NSX segment name
$defaultDomain = 'avs.lab'

# VM / Object Names
$NestedESXiHostnameToIPs = @{"esxi-${groupNumber}-${labNumber}" = "10.${groupNumber}.${labNumber}.3"}
$NFSVMDisplayName = "nfs-${groupNumber}-${labNumber}"
$VCSADisplayName = "vcsa-${groupNumber}-${labNumber}"
$RouterVMDisplayName = "router-${groupNumber}-${labNumber}"
$NewVcVAppName = "Nested-SDDC-Lab-${groupNumber}-${labNumber}"
$NewVCWorkloadDVPGName = "OnPrem-workload-${groupNumber}-${labNumber}"
$NewVCMgmtDVPGName = "OnPrem-management-${groupNumber}-${labNumber}"
$NewVCvMotionDVPGName = "OnPrem-vmotion-${groupNumber}-${labNumber}"
$NewVCUplinkDVPGName = "OnPrem-uplink-${groupNumber}-${labNumber}"
$NewVCReplicationDVPGName = "OnPrem-replication-${groupNumber}-${labNumber}"
$NewVCVDSName = "OnPrem-SDDC-VDS-${groupNumber}-${labNumber}"
$NewVCDatacenterName = "OnPrem-SDDC-Datacenter-${groupNumber}-${labNumber}"
$NewVCVSANClusterName = "OnPrem-SDDC-Cluster-${groupNumber}-${labNumber}"
$VMResourcePool = 'NestedLabs'
$VMFolder = 'NestedLabs'
$VMDatacenter = 'SDDC-Datacenter'   # original mgmt datacenter where vApp lived

# NSX Profiles created
$IPProfileName = "Group${groupNumber}-IPDiscoveryProfile"
$MACProfileName = "Group${groupNumber}-MACDiscoveryProfile"
$SegSecProfileName = "Group${groupNumber}-SegmentSecurityProfile"
$SegSecBinding   = "Lab${groupNumber}-segment_security_binding_map"
$DiscBinding     = "Lab${groupNumber}-segment_discovery_binding_map"

# Static Route ID (same as vApp name in deployment stage)
$StaticRouteId = $NewVcVAppName

# Helper for WhatIf semantics
function Invoke-Delete {
    param(
        [scriptblock]$Action,
        [string]$Description
    )
    if($WhatIf){ Write-Log "WHATIF: Would remove: $Description" 'Yellow' }
    else {
        try { & $Action; Write-Log "Removed: $Description" }
        catch { Write-Log "Skip/Failed removing $Description : $($_.Exception.Message)" 'Red' }
    }
}

# Connect to vCenter (management) first
Write-Log "Connecting to vCenter $VIServer" 'White'
Import-Module VCF.PowerCLI -ErrorAction Stop
$viConnection = $null
try { $viConnection = Connect-VIServer -Server $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue }
catch { Write-Log "Connection to vCenter failed: $($_.Exception.Message)" 'Red'; exit 1 }

# Gather objects for deletion (best-effort; continue on errors)
# 1. Power off & delete workload / router / vcsa / nfs / esxi VMs
$vmNames = @()
$vmNames += $VCSADisplayName
$vmNames += $NFSVMDisplayName
$vmNames += $RouterVMDisplayName
$vmNames += $NestedESXiHostnameToIPs.Keys

Write-Log 'Processing VM deletions' 'Cyan'
foreach($name in $vmNames | Sort-Object -Unique){
    $vm = Get-VM -Name $name -Server $viConnection -ErrorAction SilentlyContinue
    if($vm){
        if($vm.PowerState -ne 'PoweredOff'){
            Invoke-Delete -Description "Power off VM $name" -Action { Stop-VM -VM $vm -Confirm:$false -ErrorAction Stop }
        }
        Invoke-Delete -Description "Delete VM $name" -Action { Remove-VM -VM $vm -DeletePermanently -Confirm:$false -ErrorAction Stop }
    } else { Write-Log "VM $name not found (already removed)" 'Yellow' }
}

# 2. Delete vApp (if exists) in mgmt vCenter
$vapp = Get-VApp -Name $NewVcVAppName -Server $viConnection -ErrorAction SilentlyContinue
if($vapp){ Invoke-Delete -Description "vApp $NewVcVAppName" -Action { Remove-VApp -VApp $vapp -Confirm:$false -ErrorAction Stop } }
else { Write-Log "vApp $NewVcVAppName not found" 'Yellow' }

# 3. Remove VM Folder (if empty)
$folder = Get-Folder -Name $VMFolder -Server $viConnection -ErrorAction SilentlyContinue
if($folder){
    $children = Get-VM -Location $folder -ErrorAction SilentlyContinue
    if(!$children){ Invoke-Delete -Description "Folder $VMFolder" -Action { Remove-Folder -Folder $folder -Confirm:$false -ErrorAction Stop } }
    else { Write-Log "Folder $VMFolder not empty, skipping" 'Yellow' }
}

# 4. Remove Resource Pool if empty
$rpool = Get-ResourcePool -Name $VMResourcePool -Server $viConnection -ErrorAction SilentlyContinue
if($rpool){
    $rpoolVMs = Get-VM -Location $rpool -ErrorAction SilentlyContinue
    if(!$rpoolVMs){ Invoke-Delete -Description "ResourcePool $VMResourcePool" -Action { Remove-ResourcePool -ResourcePool $rpool -Confirm:$false -ErrorAction Stop } }
    else { Write-Log "ResourcePool $VMResourcePool not empty, skipping" 'Yellow' }
}

# Disconnect mgmt vCenter (keep connection if VCSA removal changes anything)
if($viConnection){ Disconnect-VIServer -Server $viConnection -Confirm:$false }

# NOTE: The nested VCSA & its internal objects (Datacenter/Cluster/VDS/Portgroups) are deleted when the VCSA VM is deleted above.
# No need to connect inside nested environment for cleanup.

# NSX Cleanup
Write-Log "Connecting to NSX $nsxtHost" 'White'
$nsxtConnection = $null
try { $nsxtConnection = Connect-NsxtServer -Server $nsxtHost -User $nsxtUser -Password $nsxtPass }
catch { Write-Log "NSX connection failed: $($_.Exception.Message)" 'Red' }

if($nsxtConnection){
    # Find T1 Name (pattern TNT**-T1) same as deployment logic
    $t1svc = Get-NsxtService -Name com.vmware.nsx.logical_routers
    $t1list = $t1Svc.list()
    $t1result = $t1list.results | Where-Object { $_.display_name -like 'TNT**-T1' }
    $t1Name = $t1result.display_name

    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($nsxtUser):$($nsxtPass)"))
    $Header = @{ Authorization = "Basic $base64AuthInfo" }

    # 1. Remove static route (if exists)
    try {
        $routeUrl = "https://$nsxtHost/policy/api/v1/infra/tier-1s/$t1Name/static-routes/$StaticRouteId"
        $existing = Invoke-WebRequest -Uri $routeUrl -Headers $Header -Method GET -SkipCertificateCheck -SkipHttpErrorCheck
        if($existing.StatusCode -eq 200){
            Invoke-Delete -Description "NSX Static Route $StaticRouteId" -Action { Invoke-RestMethod -Uri $routeUrl -Headers $Header -Method DELETE -SkipCertificateCheck }
        } else { Write-Log "Static route $StaticRouteId not found" 'Yellow' }
    } catch { Write-Log "Static route lookup failed or not present" 'Yellow' }

    # 2. Remove segment bindings (security & discovery)
    $secBindUrl = "https://$nsxtHost/policy/api/v1/infra/tier-1s/$t1Name/segments/$VMNetwork/segment-security-profile-binding-maps/$SegSecBinding"
    try {
        $resp = Invoke-WebRequest -Uri $secBindUrl -Headers $Header -Method GET -SkipCertificateCheck -SkipHttpErrorCheck
        if($resp.StatusCode -eq 200){ Invoke-Delete -Description "Segment Security Binding $SegSecBinding" -Action { Invoke-RestMethod -Uri $secBindUrl -Headers $Header -Method DELETE -SkipCertificateCheck } }
    } catch {}

    $discBindUrl = "https://$nsxtHost/policy/api/v1/infra/tier-1s/$t1Name/segments/$VMNetwork/segment-discovery-profile-binding-maps/$DiscBinding"
    try {
        $resp = Invoke-WebRequest -Uri $discBindUrl -Headers $Header -Method GET -SkipCertificateCheck -SkipHttpErrorCheck
        if($resp.StatusCode -eq 200){ Invoke-Delete -Description "Segment Discovery Binding $DiscBinding" -Action { Invoke-RestMethod -Uri $discBindUrl -Headers $Header -Method DELETE -SkipCertificateCheck } }
    } catch {}

    # 3. Remove segment itself
    $segmentURL = "https://$nsxtHost/policy/api/v1/infra/tier-1s/$t1Name/segments/$VMNetwork"
    try {
        $resp = Invoke-WebRequest -Uri $segmentURL -Headers $Header -Method GET -SkipCertificateCheck -SkipHttpErrorCheck
        if($resp.StatusCode -eq 200){ Invoke-Delete -Description "NSX Segment $VMNetwork" -Action { Invoke-RestMethod -Uri $segmentURL -Headers $Header -Method DELETE -SkipCertificateCheck } }
        else { Write-Log "Segment $VMNetwork not found" 'Yellow' }
    } catch { Write-Log "Segment $VMNetwork not found or error" 'Yellow' }

    # 4. Remove profiles (IP, MAC, Segment Security) only if not used by another lab (simple heuristic by name uniqueness)
    foreach($profItem in @(
        @{Name=$IPProfileName; Url="https://$nsxtHost/policy/api/v1/infra/ip-discovery-profiles/$IPProfileName"},
        @{Name=$MACProfileName; Url="https://$nsxtHost/policy/api/v1/infra/mac-discovery-profiles/$MACProfileName"},
        @{Name=$SegSecProfileName; Url="https://$nsxtHost/policy/api/v1/infra/segment-security-profiles/$SegSecProfileName"}
    )){
        try {
            $resp = Invoke-WebRequest -Uri $profItem.Url -Headers $Header -Method GET -SkipCertificateCheck -SkipHttpErrorCheck
            if($resp.StatusCode -eq 200){ Invoke-Delete -Description "NSX Profile $($profItem.Name)" -Action { Invoke-RestMethod -Uri $profItem.Url -Headers $Header -Method DELETE -SkipCertificateCheck } }
        } catch {}
    }

    Write-Log 'Disconnecting from NSX' 'White'
    Disconnect-NsxtServer -Server $nsxtHost -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
}

Write-Log 'Cleanup Completed' 'Cyan'
Write-Log 'Summary:' 'Magenta'
Write-Log " - Group: $group"
Write-Log " - Lab: $lab"
if($WhatIf){ Write-Log 'Executed in WHATIF mode: no deletions performed' 'Yellow' }

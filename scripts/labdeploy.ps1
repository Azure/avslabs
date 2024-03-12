# Credits to:
# William Lam - VMware
# Website: www.williamlam.com
# Roberto Canton & Husam Hilal - Microsoft GPS US
# Website: www.avshub.io

param (
    # Description: "Group number for the set of nested labs to deploy."
    [Parameter(Mandatory)]
    [ValidateRange(1, 50)]
    [Alias("GroupNumber")]
    [Int] $group,
    
    # Description: "Number of nested labs to be deployed."
    [Parameter(Mandatory)]
    [ValidateRange(1, 50)]
    [Alias("LabNumber")]
    [Int] $lab,

    # Description: "Is deployment in fully automated mode. Default to $false."
    [Parameter()]
    [Alias("IsAutomated")] 
    [switch] $automated = $false,

    # Description: "AVS configuration hashtable."
    [Parameter()]
    [Alias("Credentials")] 
    [hashtable] $AVSInfo
)
#Examples:
# labdeploy.ps1 -group 1 -lab 1
# labdeploy.ps1 -group 1 -lab 2 -automated
# labdeploy.ps1 -group 1 -lab 2 -automated -AVSInfo $AVSInfo

$ErrorActionPreference = "Stop"
$timeStamp = Get-Date -Format "MM-dd-yyyy_hh:mm:ss"
$timeStamp = $timeStamp.replace(':', '.')
$verboseLogFile = "nested-lab-${group}-${lab}-${timeStamp}.log"
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [String]$message
    )

    $timeStamp = Get-Date -Format "MM-dd-yyyy_hh:mm:ss"

    Write-Host -NoNewline -ForegroundColor White "[$timestamp]"
    Write-Host -ForegroundColor Green " $message"
    $logMessage = "[$timeStamp] $message"
    $logMessage | Out-File -Force -LiteralPath .\$verboseLogFile -Append
}

Write-Log "Reading argurments, starting build process ........"
Write-Log " - Group Number is $group"
Write-Log " - Lab Number is $lab"
Write-Log " - Automation is $automated"

$groupNumber = $group
$labNumber = $lab

# Local Directory Information
$mypath = Get-Location
Write-Log "Local path is $mypath"

# Reading credentials
if ( $AVSInfo.Count -eq 0) {
    # Reading from nestedlabs.yml, setting variables for easier identification
    Write-Log "Reading from nestedlabs.yml file"
    Import-Module powershell-yaml
    [string]$fileContent = Get-Content -Raw 'nestedlabs.yml'
    $config = ConvertFrom-YAML $fileContent
}
else {
    Write-Log "Getting AVS SDDC Credentials through Parameter"
    $config = $AVSInfo
}

# vCenter Server Variables
$VIServer = $config.AVSvCenter.IP 
$VIUsername = $config.AVSvCenter.Username
$VIPassword = $config.AVSvCenter.Password

Write-Log "vCenter Host: $VIServer"

# NSX-T Server Variables
$nsxtHost = $config.AVSNSXT.IP
$nsxtUser = $config.AVSNSXT.Username
$nsxtPass = $config.AVSNSXT.Password

Write-Log "NSX-T Host: $nsxtHost"

# AVS NSX-T Configurations
$VMNetwork = "Group-${groupNumber}-${labNumber}-NestedLab"
$VMNetworkCIDR = "10.${groupNumber}.${labNumber}.1/24"

# Full Path to both the Nested ESXi VA and Extracted VCSA ISO
$NestedESXiApplianceOVA = "${mypath}\Templates\Nested_ESXi7.0u3c.ova"
$VCSAInstallerPath = "${mypath}\Templates\VCSA7-Install"
$PhotonNFSOVA = "${mypath}\Templates\PhotonOS_NFS_Appliance_0.1.0.ova"
$PhotonOSOVA = "${mypath}\Templates\app-a-standalone.ova"
$RouterOVA = "${mypath}\Templates\jammy-server-cloudimg-amd64.ova"
$RouterUserDataPath = "${mypath}\router-userdata.yaml"

# Nested ESXi VMs to deploy
$NestedESXiHostnameToIPs = @{
    "esxi-${groupNumber}-${labNumber}" = "10.${groupNumber}.${labNumber}.3"
    #"esxi-${groupNumber}-${labNumber}" = "10.${groupNumber}.${labNumber}.4"
    #"esxi-${groupNumber}-${labNumber}" = "10.${groupNumber}.${labNumber}.5"
}

# Nested ESXi VM Resources
$NestedESXivCPU = "16" #Cores
$NestedESXivMEM = "48" #GB

# Defaults
$defaultPassword = "MSFTavs1!"
$defaultDomain = "avs.lab"

# Nested NFS Information
$NFSVMDisplayName = "nfs-${groupNumber}-${labNumber}"
$NFSVMHostname = "nfs-${groupNumber}-${labNumber}.${defaultDomain}"
$NFSVMIPAddress = "10.${groupNumber}.${labNumber}.7"
$NFSVMPrefix = "24"
$NFSVMVolumeLabel = "nfs"
$NFSVMCapacity = "500" #GB
$NFSVMRootPassword = $defaultPassword

# If Routing for VM segment is needed
$RouterVMDisplayName = "router-${groupNumber}-${labNumber}"
$RouterVMHostname = "router-${groupNumber}-${labNumber}.avs.lab"
$RouterVMIPAddress = "10.${groupNumber}.${labNumber}.8"
$RouterVMPrefix = "24"
$RouterVMPassword = $defaultPassword

# VCSA Deployment Configuration
$VCSADeploymentSize = "small"
$VCSADisplayName = "vcsa-${groupNumber}-${labNumber}"
$VCSAIPAddress = "10.${groupNumber}.${LabNumber}.2"
$VCSAHostname = "10.${groupNumber}.${LabNumber}.2" #Change to IP if you don't have valid DNS
$VCSAPrefix = "24"
$VCSASSODomainName = $defaultDomain
$VCSASSOPassword = $defaultPassword
$VCSARootPassword = $defaultPassword
$VCSASSHEnable = $true

# General Deployment Configuration for Nested ESXi, VCSA & NSX VMs
$VMDatacenter = "SDDC-Datacenter"
$VMCluster = "Cluster-1"
$VMResourcePool = "NestedLabs"
$VMFolder = "NestedLabs"
$VMDatastore = "vsanDatastore"

$VMNetmask = "255.255.255.0"
$VMGateway = "10.${groupNumber}.${labNumber}.1"
$VMDNS = "1.1.1.1"
$VMNTP = "pool.ntp.org"
$VMPassword = $defaultPassword
$VMDomain = $defaultDomain
#$VMSyslog = "192.168.1.10"

# Applicable to Nested ESXi only
$ESXiVMSSH = $true

# Name of new vSphere Datacenter/Cluster when VCSA is deployed
$NewVCDatacenterName = "OnPrem-SDDC-Datacenter-${groupNumber}-${labNumber}"
$NewVCVSANClusterName = "OnPrem-SDDC-Cluster-${groupNumber}-${labNumber}"
$NewVCVDSName = "OnPrem-SDDC-VDS-${groupNumber}-${labNumber}"
$NewVCMgmtDVPGName = "OnPrem-management-${groupNumber}-${labNumber}"
$NewVCvMotionDVPGName = "OnPrem-vmotion-${groupNumber}-${labNumber}"
$NewVCUplinkDVPGName = "OnPrem-uplink-${groupNumber}-${labNumber}"
$NewVCReplicationDVPGName = "OnPrem-replication-${groupNumber}-${labNumber}"
$NewVCWorkloadDVPGName = "OnPrem-workload-${groupNumber}-${labNumber}"
$NewVCWorkloadVMFormat = "Workload-${groupNumber}-${labNumber}-" # workload-01,02,03,etc
$NewVcWorkloadVMCount = 2
$NewVcVAppName = "Nested-SDDC-Lab-${groupNumber}-${labNumber}"

# Advanced Configurations
# Set to $true only if you have DNS (forward/reverse) for ESXi hostnames
$addHostByDnsName = $false

#### DO NOT EDIT BEYOND HERE ####
$preCheck = $true
$confirmDeployment = $true
$deployNFSVM = $true
$deployNestedESXiVMs = $true
$deployVCSA = $true
$setupNewVC = $true
$addESXiHostsToVC = $true
$configureESXiStorage = $true
$configureVDS = $true
$moveVMsIntovApp = $true
$deployWorkload = $true
$deployRouting = $true

$vcsaSize2MemoryStorageMap = @{
    "tiny"   = @{"cpu" = "2"; "mem" = "12"; "disk" = "415" };
    "small"  = @{"cpu" = "4"; "mem" = "19"; "disk" = "480" };
    "medium" = @{"cpu" = "8"; "mem" = "28"; "disk" = "700" };
    "large"  = @{"cpu" = "16"; "mem" = "37"; "disk" = "1065" };
    "xlarge" = @{"cpu" = "24"; "mem" = "56"; "disk" = "1805" }
}

$esxiTotalCPU = 12
$vcsaTotalCPU = 0
$esxiTotalMemory = 48
$vcsaTotalMemory = 0
$esxiTotalStorage = 0

$StartTime = Get-Date

if ($preCheck) {
    if (!(Test-Path $NestedESXiApplianceOVA)) {
        Write-Host -ForegroundColor Red "`nUnable to find $NestedESXiApplianceOVA ...`n"
        exit
    }

    if (!(Test-Path $VCSAInstallerPath)) {
        Write-Host -ForegroundColor Red "`nUnable to find $VCSAInstallerPath ...`n"
        exit
    }

    if (!(Test-Path $PhotonNFSOVA)) {
        Write-Host -ForegroundColor Red "`nUnable to find $PhotonNFSOVA ...`n"
        exit
    }

    if ($deployWorkload) {
        if (!(Test-Path $PhotonOSOVA)) {
            Write-Host -ForegroundColor Red "`nUnable to find $PhotonOSOVA ...`n"
            exit
        }
    }

    if ($deployRouting) {
        if (!(Test-Path $RouterOVA)) {
            Write-Host -ForegroundColor Red "`nUnable to find $RouterOVA ...`n"
            exit
        }
    }

    if ($PSVersionTable.PSEdition -ne "Core") {
        Write-Host -ForegroundColor Red "`tPowerShell Core was not detected, please install that before continuing ... `n"
        exit
    }
}

if ($confirmDeployment) {
    Write-Host -ForegroundColor Magenta "`nPlease confirm the following configuration will be deployed:`n"

    Write-Host -ForegroundColor Yellow "---- Nested SDDC Automated Lab Deployment Configuration ---- "
    Write-Host -NoNewline -ForegroundColor Green "SDDC Provider: "
    Write-Host -ForegroundColor White "Microsoft"
    Write-Host -NoNewline -ForegroundColor Green "VMware Cloud Service: "
    Write-Host -ForegroundColor White "Azure VMware Solution (AVS)"

    Write-Host -NoNewline -ForegroundColor Green "`nNested ESXi Image Path: "
    Write-Host -ForegroundColor White $NestedESXiApplianceOVA
    Write-Host -NoNewline -ForegroundColor Green "VCSA Image Path: "
    Write-Host -ForegroundColor White $VCSAInstallerPath

    Write-Host -NoNewline -ForegroundColor Green "NFS Image Path: "
    Write-Host -ForegroundColor White $PhotonNFSOVA

    if ($deployWorkload) {
        Write-Host -NoNewline -ForegroundColor Green "PhotonOS Image Path: "
        Write-Host -ForegroundColor White $PhotonOSOVA
    }

    Write-Host -ForegroundColor Yellow "`n---- vCenter Server Deployment Target Configuration ----"
    Write-Host -NoNewline -ForegroundColor Green "vCenter Server Address: "
    Write-Host -ForegroundColor White $VIServer
    Write-Host -NoNewline -ForegroundColor Green "VM Network: "
    Write-Host -ForegroundColor White $VMNetwork

    Write-Host -NoNewline -ForegroundColor Green "VM Cluster: "
    Write-Host -ForegroundColor White $VMCluster
    Write-Host -NoNewline -ForegroundColor Green "VM Resource Pool: "
    Write-Host -ForegroundColor White $VMResourcePool
    Write-Host -NoNewline -ForegroundColor Green "VM Storage: "
    Write-Host -ForegroundColor White $VMDatastore
    Write-Host -NoNewline -ForegroundColor Green "VM vApp: "
    Write-Host -ForegroundColor White $NewVcVAppName

    Write-Host -ForegroundColor Yellow "`n---- vESXi Configuration ----"
    Write-Host -NoNewline -ForegroundColor Green "# of Nested ESXi VMs: "
    Write-Host -ForegroundColor White $NestedESXiHostnameToIPs.count
    Write-Host -NoNewline -ForegroundColor Green "vCPU: "
    Write-Host -ForegroundColor White $NestedESXivCPU
    Write-Host -NoNewline -ForegroundColor Green "vMEM: "
    Write-Host -ForegroundColor White "$NestedESXivMEM GB"
    Write-Host -NoNewline -ForegroundColor Green "NFS Storage: "
    Write-Host -ForegroundColor White "$NFSVMCapacity GB"
    Write-Host -NoNewline -ForegroundColor Green "IP Address(s): "
    Write-Host -ForegroundColor White $NestedESXiHostnameToIPs.Values
    Write-Host -NoNewline -ForegroundColor Green "Netmask "
    Write-Host -ForegroundColor White $VMNetmask
    Write-Host -NoNewline -ForegroundColor Green "Gateway: "
    Write-Host -ForegroundColor White $VMGateway
    Write-Host -NoNewline -ForegroundColor Green "DNS: "
    Write-Host -ForegroundColor White $VMDNS
    Write-Host -NoNewline -ForegroundColor Green "NTP: "
    Write-Host -ForegroundColor White $VMNTP
    Write-Host -NoNewline -ForegroundColor Green "Syslog: "
    Write-Host -ForegroundColor White $VMSyslog
    Write-Host -NoNewline -ForegroundColor Green "Enable SSH: "
    Write-Host -ForegroundColor White $ESXiVMSSH

    Write-Host -ForegroundColor Yellow "`n---- VCSA Configuration ----"
    Write-Host -NoNewline -ForegroundColor Green "Deployment Size: "
    Write-Host -ForegroundColor White $VCSADeploymentSize
    Write-Host -NoNewline -ForegroundColor Green "SSO Domain: "
    Write-Host -ForegroundColor White $VCSASSODomainName
    Write-Host -NoNewline -ForegroundColor Green "Enable SSH: "
    Write-Host -ForegroundColor White $VCSASSHEnable
    Write-Host -NoNewline -ForegroundColor Green "Hostname: "
    Write-Host -ForegroundColor White $VCSAHostname
    Write-Host -NoNewline -ForegroundColor Green "IP Address: "
    Write-Host -ForegroundColor White $VCSAIPAddress
    Write-Host -NoNewline -ForegroundColor Green "Netmask "
    Write-Host -ForegroundColor White $VMNetmask
    Write-Host -NoNewline -ForegroundColor Green "Gateway: "
    Write-Host -ForegroundColor White $VMGateway

    $esxiTotalCPU = $NestedESXiHostnameToIPs.count * [int]$NestedESXivCPU
    $esxiTotalMemory = $NestedESXiHostnameToIPs.count * [int]$NestedESXivMEM

    $esxiTotalStorage = [int]$NFSCapacity

    $vcsaTotalCPU = $vcsaSize2MemoryStorageMap.$VCSADeploymentSize.cpu
    $vcsaTotalMemory = $vcsaSize2MemoryStorageMap.$VCSADeploymentSize.mem
    $vcsaTotalStorage = $vcsaSize2MemoryStorageMap.$VCSADeploymentSize.disk

    Write-Host -ForegroundColor Yellow "`n---- Resource Requirements ----"
    Write-Host -NoNewline -ForegroundColor Green "ESXi     VM CPU: "
    Write-Host -NoNewline -ForegroundColor White $esxiTotalCPU
    Write-Host -NoNewline -ForegroundColor Green " ESXi     VM Memory: "
    Write-Host -NoNewline -ForegroundColor White $esxiTotalMemory "GB "
    Write-Host -NoNewline -ForegroundColor Green "ESXi     VM Storage: "
    Write-Host -ForegroundColor White $esxiTotalStorage "GB"
    Write-Host -NoNewline -ForegroundColor Green "VCSA     VM CPU: "
    Write-Host -NoNewline -ForegroundColor White $vcsaTotalCPU
    Write-Host -NoNewline -ForegroundColor Green " VCSA     VM Memory: "
    Write-Host -NoNewline -ForegroundColor White $vcsaTotalMemory "GB "
    Write-Host -NoNewline -ForegroundColor Green "VCSA     VM Storage: "
    Write-Host -ForegroundColor White $vcsaTotalStorage "GB"

    $nfsCPU = 2
    $nfsMemory = 4
    $nfsStorage = $NFSCapacity

    Write-Host -NoNewline -ForegroundColor Green "NFS      VM CPU: "
    Write-Host -NoNewline -ForegroundColor White $nfsCPU
    Write-Host -NoNewline -ForegroundColor Green " NFS      VM Memory: "
    Write-Host -NoNewline -ForegroundColor White $nfsMemory " GB "
    Write-Host -NoNewline -ForegroundColor Green "NFS      VM Storage: "
    Write-Host -ForegroundColor White $NFSVMCapacity " GB"
    
    $routerCPU = 2
    $routerMemory = 1
    $routerStorage = 10
    Write-Host -NoNewline -ForegroundColor Green "Router   VM CPU: "
    Write-Host -NoNewline -ForegroundColor White $routerCPU
    Write-Host -NoNewline -ForegroundColor Green " Router   VM Memory: "
    Write-Host -NoNewline -ForegroundColor White $routerMemory " GB "
    Write-Host -NoNewline -ForegroundColor Green "Router   VM Storage: "
    Write-Host -ForegroundColor White $routerStorage " GB"

    Write-Host -ForegroundColor White "---------------------------------------------"
    Write-Host -NoNewline -ForegroundColor Green "Total CPU: "
    Write-Host -ForegroundColor White ($esxiTotalCPU + $vcsaTotalCPU + $nsxManagerTotalCPU + $nsxEdgeTotalCPU + $nfsCPU + $routerCPU)
    Write-Host -NoNewline -ForegroundColor Green "Total Memory: "
    Write-Host -ForegroundColor White ($esxiTotalMemory + $vcsaTotalMemory + $nsxManagerTotalMemory + $nsxEdgeTotalMemory + $nfsMemory + $routerMemory) "GB"
    Write-Host -NoNewline -ForegroundColor Green "Total Storage: "
    Write-Host -ForegroundColor White ($esxiTotalStorage + $vcsaTotalStorage + $nsxManagerTotalStorage + $nsxEdgeTotalStorage + $nfsStorage + $routerStorage) "GB"
    Write-Host -ForegroundColor White "---------------------------------------------"
    Write-Host -ForegroundColor Magenta "`nWould you like to proceed with this deployment?`n"
    if (-Not $automated) {
        $answer = Read-Host -Prompt "Do you accept (Y or N)"
        if ($answer -ne "Y" -or $answer -ne "y") {
            exit
        }
    }
    else {
        Write-Host -ForegroundColor Green "`nAutomated Deployment!`n"
    }

    Write-Host -ForegroundColor Green "`n=========  =============  =========`n"
    #Clear-Host // commenting this cmdlet to make script eligible to be invoked using ForEach-Object -Parallel
}

# Import the PowerCLI module
Write-Log "Importing PowerCLI PowerShell Module"
Import-Module VMware.PowerCLI
Write-Log "Imported PowerCLI PowerShell Module Successfully"

if ( $deployNFSVM -or $deployNestedESXiVMs -or $deployVCSA) {

    # Connecting to vCenter Server
    try {
        Write-Log "Connecting to Management vCenter Server $VIServer ..."
        $viConnection = Connect-VIServer -Server $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue -ErrorAction Stop
        Write-Log "Connected to vCenter Server"
    }catch {
        Write-Log "Failed to connect to $VIServer. Error: $_"
        exit
    }

    # Connecting to NSX-T Manager
    Write-Log "Connecting to NSX-T Server $nsxtHost ..."
    $nsxtConnection = Connect-NsxtServer -Server ${nsxtHost} -User ${nsxtUser} -Password ${nsxtPass}
    Write-Log "Connected to NSX-T Server"

    # Create Resource Pool
    Write-Log "Creating $VMResourcePool if it does not exist ......"

    if (-Not (Get-ResourcePool -Name $VMResourcePool -Server $viConnection -ErrorAction Ignore)) {
        $newrp = New-ResourcePool -Server $viConnection -Location 'Cluster-1' -Name $VMResourcePool
        Write-Log "Creation of $VMResourcePool completed."
    }

    # Get Transport Zone ID: Transport Zone Overlay = $tzoneOverlay, Transport Zone Overlay ID = $tzoneOverlayID, tzPath
    Write-Log "Getting Transport Zone Overlay ID from NSX-T"

    $tzSvc = Get-NsxtService -Name com.vmware.nsx.transport_zones
    $tzones = $tzSvc.list()
    $tzoneOverlay = $tzones.results | Where-Object { $_.display_name -like 'TNT**-OVERLAY-TZ' }
    #TODO: Test if commenting the following line will cause any problem
    #$tzoneOverlayID = $tzoneOverlay.id
    $tzoneOverlay = $tzoneOverlay.display_name

    #TODO: Get-NsxtPolicyService is depricated, need to find alternative

    #Solution is as below but need to test switching from Connect-NsxtServer to Connect-NsxServer 
    <#
    #References: https://blogs.vmware.com/networkvirtualization/2022/05/navigating-nsx-module-in-powercli-12-6.html/
    #            https://github.com/vmware-samples/nsx-t/tree/master/powercli
    Connect-NsxServer -Server $nsxtHost -User $nsxtUser -Password $nsxtPass
    $tzs = Invoke-ListTransportZonesForEnforcementPoint -EnforcementpointId "default" -SiteId "default"
    $tzPath = ($tzs.Results | Where-Object { $_.DisplayName -match 'TNT\d{2}-OVERLAY-TZ' }).Path | Select-Object -First 1
    #>

    #TODO: Test if commenting the following line will cause any problem
    #$transportZonePolicyService = Get-NsxtPolicyService -Name "com.vmware.nsx_policy.infra.sites.enforcement_points.transport_zones"
    #$tzPath = ($transportZonePolicyService.list("default", "default").results | where { $_.display_name -like "TNT**-OVERLAY-TZ" }).path

    # Get Default T1 Gateway
    Write-Log "Getting NSX-T Default T1 Gateway"

    $t1svc = Get-NsxtService -Name com.vmware.nsx.logical_routers
    $t1list = $t1Svc.list()
    $t1result = $t1list.results | Where-Object { $_.display_name -like 'TNT**-T1' }
    #TODO: Test if commenting the following line will cause any problem
    #$t1ID = $t1result.id
    $t1Name = $t1result.display_name

    # Create Segment Profiles

    $getswitchprof = Get-NsxtService -Name com.vmware.nsx.switching_profiles
    $getswitchproflist = $getswitchprof.list()
    $getswitchprofresult = $getswitchproflist.results | Where-Object { $_.display_name -like 'Group${groupNumber}*' }
    $switchprofName = $getswitchprofresult.display_name
    
    # Create IP Discovery Segment Profile
    
    $IPProfileName = "Group${groupNumber}-IPDiscoveryProfile"

    if ($switchprofName -contains "$IPProfileName") {
        Write-Log "$IPProfileName already exists, will use it."
    }
    else {
        Write-Log "Creating $IPProfileName......"

        $uri = "https://$nsxtHost/policy/api/v1/infra/ip-discovery-profiles/$IPProfileName"

        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($nsxtUser):$($nsxtPass)"))

        $Header = @{
            Authorization = "Basic $base64AuthInfo"
        }

        $Body = @"
        {
        "resource_type": "IPDiscoveryProfile",
        "display_name": "$IPProfileName",
        "description": "",
        "ip_v4_discovery_options": {
            "arp_snooping_config": {
            "arp_snooping_enabled": true,
            "arp_binding_limit": 100
            },
            "dhcp_snooping_enabled": true,
            "vmtools_enabled": true
        },
        "ip_v6_discovery_options": {
            "nd_snooping_config": {
            "nd_snooping_enabled": false,
            "nd_snooping_limit": 3
            },
            "dhcp_snooping_v6_enabled": false,
            "vmtools_v6_enabled": false
        },
        "tofu_enabled": true,
        "arp_nd_binding_timeout": 10,
        "duplicate_ip_detection": {
            "duplicate_ip_detection_enabled": false
        }
        }
"@

        $ipprofile = Invoke-RestMethod -Uri $uri -Headers $Header -Method Patch -Body $Body -ContentType "application/json" -SkipCertificateCheck
    }

    ### Create MAC Discovery Segment Profile

    $MACProfileName = "Group${groupNumber}-MACDiscoveryProfile"

    if ($switchprofName -contains "$MACProfileName") {
        Write-Log "$MACProfileName already exists, will use it."
    }
    else {
        Write-Log "Creating $MACProfileName......"

        $uri = "https://$nsxtHost/policy/api/v1/infra/mac-discovery-profiles/$MACProfileName"

        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($nsxtUser):$($nsxtPass)"))

        $Header = @{
            Authorization = "Basic $base64AuthInfo"
        }

        $Body = @"
        {
            "resource_type":"MacDiscoveryProfile",
            "display_name": "${MacProfileName}",
            "description": "",
            "mac_change_enabled": true,
            "mac_learning_enabled": true,
            "unknown_unicast_flooding_enabled": true,
            "mac_limit_policy": "ALLOW",
            "mac_limit": 4096
        }
"@

        $macprofile = Invoke-RestMethod -Uri $uri -Headers $Header -Method Patch -Body $Body -ContentType "application/json" -SkipCertificateCheck
    }

    # Create Segment Security Segment Profile

    $SegSecProfileName = "Group${groupNumber}-SegmentSecurityProfile"

    if ($switchprofName -contains "$SegSecProfileName") {
        Write-Log "$SegSecProfileName already exists, will use it."
    }
    else {
        Write-Log "Creating $SegSecProfileName......"

        $uri = "https://$nsxtHost/policy/api/v1/infra/segment-security-profiles/$SegSecProfileName"

        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($nsxtUser):$($nsxtPass)"))

        $Header = @{
            Authorization = "Basic $base64AuthInfo"
        }

        $Body = @"
        {
        "resource_type": "SegmentSecurityProfile",
        "id": "${SegSecProfileName}",
        "display_name": "${SegSecProfileName}",
        "description": "",
        "bpdu_filter_enable": false,
        "dhcp_server_block_enabled": false,
        "dhcp_client_block_enabled": false,
        "non_ip_traffic_block_enabled": false,
        "dhcp_server_block_v6_enabled": false,
        "dhcp_client_block_v6_enabled": false,
        "ra_guard_enabled": true
        }
"@

        $secprofile = Invoke-RestMethod -Uri $uri -Headers $Header -Method Patch -Body $Body -ContentType "application/json" -SkipCertificateCheck
    }

    ## Create Network Segment for Nested Lab
    Write-Log "Creating Network in AVS NSX-T for Nested Lab ${labNumber}"

    $segmentName = $VMNetwork
    $gatewayaddress = $VMNetworkCIDR
    Write-Log "Creating $segmentName....."

    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($nsxtUser):$($nsxtPass)"))
    $Header = @{
        Authorization = "Basic $base64AuthInfo"
    }

    $Body = @"
    {
        "display_name":"$segmentName",
        "subnets": [
            {
                "gateway_address":"$gatewayaddress"
            }
        ],
        "connectivity_path": "/infra/tier-1s/$t1Name"
    }
"@
 
    $segmentURL = "https://$nsxtHost/policy/api/v1/infra/tier-1s/$t1Name/segments/" + $segmentName
    $existingSegment = Invoke-WebRequest -Uri $segmentURL -Headers $Header -Method GET -SkipCertificateCheck -SkipHttpErrorCheck
    if ($existingSegment.StatusCode -eq 200) {
        Write-Log "A segment $segmentName already exists, will reuse it"
    } else {
        $segmentCreation = Invoke-RestMethod -Uri $segmentURL -Headers $Header -Method Patch -Body $Body -ContentType "application/json" -SkipCertificateCheck
        Write-Log "Segment $segmentName created....."
        sleep 15
    }
    
    ## Adding Security Segment Profile
    Write-Log "Adding Security Segment Profile to $segmentName ....."

    $bindingName = "Lab${groupNumber}-segment_security_binding_map"

    $uri = "https://$nsxtHost/policy/api/v1/infra/tier-1s/$t1Name/segments/${segmentName}/segment-security-profile-binding-maps/${bindingName}"

    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($nsxtUser):$($nsxtPass)"))

    $Header = @{
        Authorization = "Basic $base64AuthInfo"
    }

    $Body = @"
    {
        "resource_type": "SegmentSecurityProfileBindingMap",
        "id": "${bindingName}",
        "display_name": "${bindingName}",
        "path": "/infra/segments/${segmentName}/segment-security-profile-binding-maps/${bindingName}",
        "parent_path": "/infra/tier-1s/$t1Name/segments/${segmentName}",
        "relative_path": "${bindingName}",
        "marked_for_delete": false,
        "segment_security_profile_path": "/infra/segment-security-profiles/Group${groupNumber}-SegmentSecurityProfile"
    }
"@

    $secProfAdd = Invoke-RestMethod -Uri $uri -Headers $Header -Method Put -Body $Body -ContentType "application/json" -SkipCertificateCheck

    ## Adding Discovery Segment Profiles
    Write-Log "Adding Discovery Segment Profile to $segmentName ....."

    $bindingName = "Lab${groupNumber}-segment_discovery_binding_map"

    $uri = "https://$nsxtHost/policy/api/v1/infra/tier-1s/$t1Name/segments/${segmentName}/segment-discovery-profile-binding-maps/${bindingName}"

    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($nsxtUser):$($nsxtPass)"))

    $Header = @{
        Authorization = "Basic $base64AuthInfo"
    }

    $Body = @"
    {
        "resource_type":" SegmentDiscoveryProfileBindingMap",
        "display_name": "${bindingName}",
        "description":"",
        "mac_discovery_profile_path":"/infra/mac-discovery-profiles/Group${groupNumber}-MACDiscoveryProfile",
        "ip_discovery_profile_path":"/infra/ip-discovery-profiles/Group${groupNumber}-IPDiscoveryProfile"
    }
"@

    $discProfAdd = Invoke-RestMethod -Uri $uri -Headers $Header -Method Patch -Body $Body -ContentType "application/json" -SkipCertificateCheck

    # Get Logical Switch Information
    Write-Log "Getting Logical Switch Information for $segmentName"

    #TODO: Test if commenting the following line will cause any problem
    #$lssvc = Get-NsxtService -Name com.vmware.nsx.logical_switches
    #$lslist = $lsSvc.list()
    #$lsresult = $lslist.results | Where-Object { $_.display_name -eq "$network" }
    #$lsID = $lsresult.id
    #$lsName = $lsresult.display_name

    # Gather AVS vCenter Information
    $datastore = Get-Datastore -Server $viConnection -Name $VMDatastore | Select -First 1
    $resourcepool = Get-ResourcePool -Server $viConnection -Name $VMResourcePool
    $cluster = Get-Cluster -Server $viConnection -Name $VMCluster
    $datacenter = $cluster | Get-Datacenter
    $vmhost = $cluster | Get-VMHost | Select -First 1
}

if ($deployNestedESXiVMs) {
    $NestedESXiHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
        $VMName = $_.Key
        $VMIPAddress = $_.Value

        $ovfconfig = Get-OvfConfiguration $NestedESXiApplianceOVA
        $ovfNetworkLabel = ($ovfconfig.NetworkMapping | Get-Member -MemberType Properties).Name
        $ovfconfig.NetworkMapping.$ovfNetworkLabel.value = $VMNetwork
        Start-Sleep 15

        $ovfconfig.common.guestinfo.hostname.value = $VMName
        $ovfconfig.common.guestinfo.ipaddress.value = $VMIPAddress
        $ovfconfig.common.guestinfo.netmask.value = $VMNetmask
        $ovfconfig.common.guestinfo.gateway.value = $VMGateway
        $ovfconfig.common.guestinfo.dns.value = $VMDNS
        $ovfconfig.common.guestinfo.domain.value = $VMDomain
        $ovfconfig.common.guestinfo.ntp.value = $VMNTP
        $ovfconfig.common.guestinfo.password.value = $VMPassword
        $ovfconfig.common.guestinfo.ssh.value = $ESXiVMSSH
    
        Write-Log "Deploying Nested ESXi VM $VMName ..."
        $vm = Import-VApp -Source $NestedESXiApplianceOVA -OvfConfiguration $ovfconfig -Name $VMName -Location $resourcepool -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin -Force

        Write-Log "Adding vmnic2/vmnic3 to $VMNetwork ..."
        New-NetworkAdapter -VM $vm -Type Vmxnet3 -NetworkName $VMNetwork -StartConnected -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
        New-NetworkAdapter -VM $vm -Type Vmxnet3 -NetworkName $VMNetwork -StartConnected -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

        Write-Log "Updating vCPU Count to $NestedESXivCPU & vMEM to $NestedESXivMEM GB ..."
        Set-VM -Server $viConnection -VM $vm -NumCpu $NestedESXivCPU -MemoryGB $NestedESXivMEM -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

        Write-Log "Powering On $vmname ..."
        $vm | Start-Vm -RunAsync | Out-Null
    }
}

if ($deployNFSVM) {
    $ovfconfig = Get-OvfConfiguration $PhotonNFSOVA
    $ovfNetworkLabel = ($ovfconfig.NetworkMapping | Get-Member -MemberType Properties).Name
    $ovfconfig.NetworkMapping.$ovfNetworkLabel.value = $VMNetwork

    $ovfconfig.common.guestinfo.hostname.value = $NFSVMHostname
    $ovfconfig.common.guestinfo.ipaddress.value = $NFSVMIPAddress
    $ovfconfig.common.guestinfo.netmask.value = $NFSVMPrefix
    $ovfconfig.common.guestinfo.gateway.value = $VMGateway
    $ovfconfig.common.guestinfo.dns.value = $VMDNS
    $ovfconfig.common.guestinfo.domain.value = $VMDomain
    $ovfconfig.common.guestinfo.root_password.value = $NFSVMRootPassword
    $ovfconfig.common.guestinfo.nfs_volume_name.value = $NFSVMVolumeLabel
    $ovfconfig.Common.disk2size.value = $NFSVMCapacity

    Write-Log "Deploying PhotonOS NFS VM $NFSVMDisplayName ..."
    $vm = Import-VApp -Source $PhotonNFSOVA -OvfConfiguration $ovfconfig -Name $NFSVMDisplayName -Location $resourcepool -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin -Force

    Write-Log "Powering On $NFSVMDisplayName ..."
    $vm | Start-Vm -RunAsync | Out-Null
}

if ($deployVCSA) {
    if ($IsWindows) {
        $config = (Get-Content -Raw "$($VCSAInstallerPath)\vcsa-cli-installer\templates\install\embedded_vCSA_on_VC.json") | ConvertFrom-Json
    }
    else {
        $config = (Get-Content -Raw "$($VCSAInstallerPath)/vcsa-cli-installer/templates/install/embedded_vCSA_on_VC.json") | ConvertFrom-Json
    }

    $config.'new_vcsa'.vc.hostname = $VIServer
    $config.'new_vcsa'.vc.username = $VIUsername
    $config.'new_vcsa'.vc.password = $VIPassword
    $config.'new_vcsa'.vc.deployment_network = $VMNetwork
    $config.'new_vcsa'.vc.datastore = $datastore
    $config.'new_vcsa'.vc.datacenter = $datacenter.name
    $config.'new_vcsa'.appliance.thin_disk_mode = $true
    $config.'new_vcsa'.appliance.deployment_option = $VCSADeploymentSize
    $config.'new_vcsa'.appliance.name = $VCSADisplayName
    $config.'new_vcsa'.network.ip_family = "ipv4"
    $config.'new_vcsa'.network.mode = "static"
    $config.'new_vcsa'.network.ip = $VCSAIPAddress
    $config.'new_vcsa'.network.dns_servers[0] = $VMDNS
    $config.'new_vcsa'.network.prefix = $VCSAPrefix
    $config.'new_vcsa'.network.gateway = $VMGateway
    $config.'new_vcsa'.os.ntp_servers = $VMNTP
    $config.'new_vcsa'.network.system_name = $VCSAHostname
    $config.'new_vcsa'.os.password = $VCSARootPassword
    $config.'new_vcsa'.os.ssh_enable = $VCSASSHEnable
    $config.'new_vcsa'.sso.password = $VCSASSOPassword
    $config.'new_vcsa'.sso.domain_name = $VCSASSODomainName

    # Hack due to JSON depth issue
    $config.'new_vcsa'.vc.psobject.Properties.Remove("target")
    $config.'new_vcsa'.vc | Add-Member NoteProperty -Name target -Value "REPLACE-ME"

    if ($IsWindows) {
        Write-Log "Creating VCSA JSON Configuration file for deployment ..."
        $config | ConvertTo-Json -WarningAction SilentlyContinue | Set-Content -Path "$($ENV:Temp)\jsontemplate.json"
        $target = "[`"$VMCluster`",`"Resources`",`"$VMResourcePool`"]"
            (Get-Content -path "$($ENV:Temp)\jsontemplate.json" -Raw) -replace '"REPLACE-ME"', $target | Set-Content -path "$($ENV:Temp)\jsontemplate.json"

        Write-Log "Deploying the VCSA ..."
        Invoke-Expression "$($VCSAInstallerPath)\vcsa-cli-installer\win32\vcsa-deploy.exe install --no-ssl-certificate-verification --accept-eula --acknowledge-ceip $($ENV:Temp)\jsontemplate.json" | Out-File -Append -LiteralPath $verboseLogFile
    }
    elseif ($IsMacOS) {
        Write-Log "Creating VCSA JSON Configuration file for deployment ..."
        $config | ConvertTo-Json -WarningAction SilentlyContinue | Set-Content -Path "$($ENV:TMPDIR)jsontemplate.json"

        Write-Log "Deploying the VCSA ..."
        Invoke-Expression "$($VCSAInstallerPath)/vcsa-cli-installer/mac/vcsa-deploy install --no-ssl-certificate-verification --accept-eula --acknowledge-ceip $($ENV:TMPDIR)jsontemplate.json" | Out-File -Append -LiteralPath $verboseLogFile
    }
    elseif ($IsLinux) {
        Write-Log "Creating VCSA JSON Configuration file for deployment ..."
        $config | ConvertTo-Json -WarningAction SilentlyContinue | Set-Content -Path "/tmp/jsontemplate.json"

        Write-Log "Deploying the VCSA ..."
        Invoke-Expression "$($VCSAInstallerPath)/vcsa-cli-installer/lin64/vcsa-deploy install --no-ssl-certificate-verification --accept-eula --acknowledge-ceip /tmp/jsontemplate.json" | Out-File -Append -LiteralPath $verboseLogFile
    }
}

if ($viConnection) {
    Write-Log "Disconnecting from $VIServer ..."
    Disconnect-VIServer -Server $viConnection -Confirm:$false
}
Write-Log "Reconnecting $VIServer"
$viConnection = Connect-VIServer $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue

if ($moveVMsIntovApp) {
    Write-Log "Creating vApp $NewVcVAppName ..."
    $VApp = New-VApp -Name $NewVcVAppName -Server $viConnection -Location $resourcepool

    if (-Not (Get-Folder $VMFolder -ErrorAction Ignore)) {
        Write-Log "Creating VM Folder $VMFolder ..."
        $folder = New-Folder -Name $VMFolder -Server $viConnection -Location (Get-Datacenter $VMDatacenter | Get-Folder vm)
    }

    if ($deployNFSVM) {
        $vcsaVM = Get-VM -Name $NFSVMDisplayName -Server $viConnection
        Write-Log "Moving $NFSVMDisplayName into $NewVcVAppName vApp ..."
        Move-VM -VM $vcsaVM -Server $viConnection -Destination $VApp -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
    }

    if ($deployNestedESXiVMs) {
        Write-Log "Moving Nested ESXi VMs into $NewVcVAppName vApp ..."
        $NestedESXiHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
            $vm = Get-VM -Name $_.Key -Server $viConnection
            Move-VM -VM $vm -Server $viConnection -Destination $VApp -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
        }
    }

    if ($deployVCSA) {
        $vcsaVM = Get-VM -Name $VCSADisplayName -Server $viConnection
        Write-Log "Moving $VCSADisplayName into $NewVcVAppName vApp ..."
        Move-VM -VM $vcsaVM -Server $viConnection -Destination $VApp -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
    }

    Write-Log "Moving $NewVcVAppName to VM Folder $VMFolder ..."
    Move-VApp -Server $viConnection $NewVcVAppName -Destination (Get-Folder -Server $viConnection $VMFolder) | Out-File -Append -LiteralPath $verboseLogFile
}

if ( $deployNFSVM -or $deployNestedESXiVMs -or $deployVCSA) {
    Write-Log "Disconnecting from $VIServer ..."
    Disconnect-VIServer -Server $viConnection -Confirm:$false
}

if ($setupNewVC) {
    Write-Log "Connecting to the new VCSA ..."
    $vc = Connect-VIServer $VCSAIPAddress -User "administrator@$VCSASSODomainName" -Password $VCSASSOPassword -WarningAction SilentlyContinue -Force

    $d = Get-Datacenter -Server $vc $NewVCDatacenterName -ErrorAction Ignore
    if ( -Not $d) {
        Write-Log "Creating Datacenter $NewVCDatacenterName ..."
        New-Datacenter -Server $vc -Name $NewVCDatacenterName -Location (Get-Folder -Type Datacenter -Server $vc) | Out-File -Append -LiteralPath $verboseLogFile
    }

    $c = Get-Cluster -Server $vc $NewVCVSANClusterName -ErrorAction Ignore
    if ( -Not $c) {
        Write-Log "Creating vSphere Cluster $NewVCVSANClusterName ..."
        New-Cluster -Server $vc -Name $NewVCVSANClusterName -Location (Get-Datacenter -Name $NewVCDatacenterName -Server $vc) -DrsEnabled | Out-File -Append -LiteralPath $verboseLogFile
    }

    if ($addESXiHostsToVC) {
        $NestedESXiHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
            $VMName = $_.Key
            $VMIPAddress = $_.Value

            $targetVMHost = $VMIPAddress
            if ($addHostByDnsName) {
                $targetVMHost = $VMName
            }
            Write-Log "Adding ESXi host $targetVMHost to Cluster ..."
            Add-VMHost -Server $vc -Location (Get-Cluster -Name $NewVCVSANClusterName) -User "root" -Password $VMPassword -Name $targetVMHost -Force | Out-File -Append -LiteralPath $verboseLogFile
        }
    }

    if ($configureESXiStorage) {
        $labDatastore = "LabDatastore"
        Write-Log "Adding NFS Storage ..."
        foreach ($vmhost in Get-Cluster -Server $vc | Get-VMHost) {
            $vmhost | New-Datastore -Nfs -Name $labDatastore -Path /mnt/${NFSVMVolumeLabel} -NfsHost $NFSVMIPAddress | Out-File -Append -LiteralPath $verboseLogFile
        }
    }

    if ($configureVDS) {
        $vds = New-VDSwitch -Server $vc  -Name $NewVCVDSName -Location (Get-Datacenter -Name $NewVCDatacenterName) -Mtu 1600
        $workloadVLANid = "${labNumber}00"
        New-VDPortgroup -Server $vc -Name $NewVCMgmtDVPGName -Vds $vds | Out-File -Append -LiteralPath $verboseLogFile
        New-VDPortgroup -Server $vc -Name $NewVCvMotionDVPGName -Vds $vds | Out-File -Append -LiteralPath $verboseLogFile
        New-VDPortgroup -Server $vc -Name $NewVCUplinkDVPGName -Vds $vds | Out-File -Append -LiteralPath $verboseLogFile
        New-VDPortgroup -Server $vc -Name $NewVCReplicationDVPGName -Vds $vds | Out-File -Append -LiteralPath $verboseLogFile
        New-VDPortgroup -Server $vc -Name $NewVCWorkloadDVPGName -VLanId $workloadVLANid -Vds $vds | Out-File -Append -LiteralPath $verboseLogFile

        foreach ($vmhost in Get-Cluster -Server $vc | Get-VMHost) {
            Write-Log "Adding $vmhost to $NewVCVDSName"
            $vds | Add-VDSwitchVMHost -VMHost $vmhost | Out-Null

            $vmhostNetworkAdapter = Get-VMHost $vmhost | Get-VMHostNetworkAdapter -Physical -Name vmnic1
            $vds | Add-VDSwitchPhysicalNetworkAdapter -VMHostNetworkAdapter $vmhostNetworkAdapter -Confirm:$false
        }
    }

    # Final configure and then exit maintanence mode in case patching was done earlier
    foreach ($vmhost in Get-Cluster -Server $vc | Get-VMHost) {
        # Disable Core Dump Warning
        Get-AdvancedSetting -Entity $vmhost -Name UserVars.SuppressCoredumpWarning | Set-AdvancedSetting -Value 1 -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

        # Enable vMotion traffic
        $vmhost | Get-VMHostNetworkAdapter -VMKernel | Set-VMHostNetworkAdapter -VMotionEnabled $true -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

        if ($vmhost.ConnectionState -eq "Maintenance") {
            Set-VMHost -VMhost $vmhost -State Connected -RunAsync -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
        }
    }

    if ($deployWorkload) {
        Write-Log "Deploying Workload VMs ..."
        $vmhost = Get-Cluster -Server $vc | Get-VMHost | Select-Object -First 1
        $vcdatastore = Get-Datastore -Server $vc
        $appVMdns = "1.1.1.1"
        $appVMGateway = "10.${groupNumber}.1${labNumber}.129"
        $appVMIP = "10.${groupNumber}.1${labNumber}.128"

        $ovfconfig = Get-OvfConfiguration $PhotonOSOVA
        $ovfNetworkLabel = ($ovfconfig.NetworkMapping | Get-Member -MemberType Properties).Name
        $ovfconfig.NetworkMapping.$ovfNetworkLabel.value = $NewVCWorkloadDVPGName

        foreach ($i in 1..$NewVcWorkloadVMCount) {
            $VMName = "$NewVCWorkloadVMFormat$i"
            $a, $b, $c, $d = $appVMIP.Split(".")
            $d = [int]$d + $i+1
            $newappVMIP = "${a}.${b}.${c}.${d}"
            $ovfconfig.Common.guestinfo.dns.value = "$appVMdns"
            $ovfconfig.Common.guestinfo.gateway.value = "$appVMgateway"
            $ovfconfig.Common.guestinfo.ipaddress.value = "$newappVMip"
            $ovfconfig.Common.guestinfo.netmask.value = "27"
            
            Write-Log "Deploying $VMName with IP $newappVMIP ..."
            $vm = Import-VApp -Server $vc -Source $PhotonOSOVA -OvfConfiguration $ovfconfig -Name $VMName -VMHost $vmhost -Datastore $vcdatastore -DiskStorageFormat thin -Force    
            $vm | Start-VM -Server $vc -Confirm:$false | Out-Null
            Write-Log "$VMName deployed successfully and was powered on ..."
        }
    }

    if ($deployRouting) {
        $vmhost = Get-Cluster -Server $vc | Get-VMHost | Select-Object -First 1
        $vcdatastore = Get-Datastore -Server $vc
        
        $ovfconfig = Get-OvfConfiguration $RouterOVA

        # Primary network mapping
        $ovfNetworkLabel = ($ovfconfig.NetworkMapping | Get-Member -MemberType Properties).Name
        $ovfconfig.NetworkMapping.$ovfNetworkLabel.value = $NewVCMgmtDVPGName
   
        # Cloud Init
        $routerUserData = Get-Content -Path $RouterUserDataPath | Out-String
        $routerUserData = $routerUserData.Replace("__PRIMARY_IPADDRESS__", $RouterVMIPAddress)
        $routerUserData = $routerUserData.Replace("__PRIMARY_NETMASK__", $RouterVMPrefix)
        $routerUserData = $routerUserData.Replace("__PRIMARY_GATEWAY__", $VMGateway)
        $routerUserData = $routerUserData.Replace("__SECONDIP_ADDRESS__", "10.${groupNumber}.1${labNumber}.129")
        $routerUserData = $routerUserData.Replace("__SECONDARY_NETMASK__", "27")

        # Prepare string for b64 encoding
        $routerUserDataBytes = [System.Text.Encoding]::UTF8.GetBytes($routerUserData)

        # OVF properties
        $ovfconfig.Common.hostname.value = $RouterVMHostname
        $ovfconfig.Common.instance_id.value = New-Guid
        $ovfconfig.Common.password.value = $RouterVMPassword
        $ovfconfig.Common.user_data.value = [Convert]::ToBase64String($routerUserDataBytes)

        Write-Log "Deploying Routing VM $RouterVMDisplayName ..."
        $vm = Import-VApp -Server $vc -Source $RouterOVA -OvfConfiguration $ovfconfig -Name $RouterVMHostname -VMHost $VMhost -Datastore $vcdatastore -DiskStorageFormat thin -Force

        Write-Log "Attaching Routing VM $RouterVMDisplayName to workload segment..."
        New-NetworkAdapter -VM $vm -NetworkName $NewVCWorkloadDVPGName -StartConnected | Out-Null

        Write-Log "Powering On $RouterVMDisplayName ..."
        $vm | Start-Vm | Out-Null # wait for tools

        # Create static route on NSX segment to reach VM segment
        # Connecting to NSX-T Manager
        Write-Log "Connecting to NSX-T Server $nsxtHost ..."
        $nsxtConnection = Connect-NsxServer -Server ${nsxtHost} -User ${nsxtUser} -Password ${nsxtPass}
        Write-Log "Connected to NSX-T Server"
        # Get Default T1 Gateway
        Write-Log "Getting NSX-T Default T1 Gateway"
        $t1result = (Invoke-ListTier1 -Server $nsxtConnection).results | Where-Object { $_.DisplayName -like 'TNT**-T1' }
        $t1Name = $t1result.DisplayName

        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($nsxtUser):$($nsxtPass)"))
        $Header = @{
            Authorization = "Basic $base64AuthInfo"
        }
    
        # Remove existing route with same name
        $existingRoute = (Invoke-ListTier1StaticRoutes -Server $nsxtConnection -Tier1Id $t1Name).Results | Where-Object { 
            $_.network -eq "10.${groupNumber}.1${labNumber}.128/27"
        }
        if ($existingRoute) {
            Write-Log "Removing an exisitng route with same network target"
            $sRouteURL = "https://$nsxtHost/policy/api/v1/infra/tier-1s/$t1Name/static-routes/" + $existingRoute.Id
            Invoke-RestMethod -Uri $sRouteURL -Headers $Header -Method DELETE -ContentType "application/json" -SkipCertificateCheck
            Start-Sleep 15
        }
        
        $Body = @"
        {
            "display_name": "$NewVcVAppName",
            "network": "10.${groupNumber}.1${labNumber}.128/27",
            "next_hops":[
                {
                    "admin_distance":1,
                    "ip_address": "$RouterVMIPAddress"
                }
            ],
            "id":"$NewVcVAppName"
        }
"@
        $sRouteURL = "https://$nsxtHost/policy/api/v1/infra/tier-1s/$t1Name/static-routes/$NewVcVAppName"
        $sRoute = Invoke-RestMethod -Uri $sRouteURL -Headers $Header -Method PUT -Body $Body -ContentType "application/json" -SkipCertificateCheck
        Start-Sleep 15
        Write-Log "Static route $NewVcVAppName created....."
    }

    Write-Log "Disconnecting from new VCSA ..."
    Disconnect-VIServer $vc -Confirm:$false
}

$EndTime = Get-Date
$duration = [math]::Round((New-TimeSpan -Start $StartTime -End $EndTime).TotalMinutes, 2)

Write-Log "Nested SDDC Lab Deployment Complete!"
Write-Log "-StartTime: $StartTime"
Write-Log "-EndTime: $EndTime"
Write-Log "-Duration: $duration minutes"
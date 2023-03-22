###################################################################################################################################################

# Create or Delete users for GPSUS Workshop

function Initialize-GroupAccounts {

    param (
        [Parameter(Mandatory)]
        [ValidateRange(1, 50)]
        [Int] $NumberOfGroups, #How many Groups?

        [Parameter(Mandatory = $true)]
        [bool]$Operation #create or delete the user accounts: $true -> Create , $false -> Delete
    )

    for ($i = 1; $i -le $numberOfGroups; $i++) {
        $username = "GPSUS-Group" + $i
        $password = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 16 | ForEach-Object { [char]$_ })
        # $password = $([guid]::NewGuid()).ToString().Substring(0,13)
        $upn = $username + "@vmwaresales101outlook.onmicrosoft.com"
    
        if ($Operation) {
            az ad user create --display-name $username --password $password --user-principal-name $upn
            Write-Host User $upn created with password $password -ForegroundColor Green
        }
        elseif (!$Operation) {
            az ad user delete --id $upn
            Write-Host User $upn deleted successfully -ForegroundColor Green
        }
        else {
            #This code will not be executed. But left for future enhancement
            az ad user update --id $upn --account-enabled $false
            Write-Host User $upn disabled successfully -ForegroundColor Green
        }
    }

}

###################################################################################################################################################
# Execution Examples:
###################################################################################################################################################

Initialize-GroupAccounts -NumberOfGroups 10 -Operation $false

###################################################################################################################################################
###################################################################################################################################################

# Create Group Accounts, Assign Roles for Group user accounts on Azure Resource Groups for GPSUS Workshop, and Delete Group Accounts

function Set-GroupAccountsPermissionsAndPasswords {
    param (
        [Parameter()]
        [String]$Prefix,

        [Parameter()]
        [String]$PasswordPrefix,

        [Parameter(Mandatory = $true)]
        [ValidateSet(2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 34, 36, 38, 40)]
        [Int]$NumberOfLabs,
   
        [Parameter()]
        [switch] $PasswordsOnly = $false,

        [Parameter()]
        [switch] $CreateAccounts = $false,

        [Parameter()]
        [switch] $DeleteAccounts = $false
    )


    Write-Host "Script Started"

    #Create GPSUS-Group<x> accounts
    if ($CreateAccounts) {
        Initialize-GroupAccounts -NumberOfGroups $NumberOfLabs -Operation $true
    }

    #Delete GPSUS-Group<x> accounts
    if ($DeleteAccounts) {
        Initialize-GroupAccounts -NumberOfGroups $NumberOfLabs -Operation $false
    }

    $ResourceGroupSuffix = "PrivateCloud", "Operational", "Network", "Jumpbox"
    
    if ($NumberOfLabs % 2 -eq 0) {
        $numbers = 1..$NumberOfLabs
        $pairs = @()
        for ($i = 0; $i -lt $numbers.Count; $i += 2) {
            if ($i + 1 -lt $numbers.Count) {
                $pairs += , @($numbers[$i], $numbers[$i + 1])
            }
        }

        Write-Host "Number of Group Pairs:" $pairs.Count
        Initialize-GroupAccounts -NumberOfGroups 10 -Operation $false
        foreach ( $pair in $pairs ) {
            foreach ($x in $pair) {
                Write-Host
                Write-Host Group $x
                $accountId = "GPSUS-Group" + $x + "@vmwaresales101outlook.onmicrosoft.com"
                $accountPassword = $PasswordPrefix + $x + "-AVS!"
                Write-Host $accountId
            
                #Resetting Group Accounts Passwords
                Write-Host "Resetting password with provided password prefix "
                az ad user update --id $accountId --password $accountPassword --force-change-password-next-sign-in false

                if (!$PasswordsOnly && !$CreateAccounts && !$DeleteAccounts) {
                    #Assiging permessions for the Group Accounts over Azure Resource Groups for each AVS Lab Environment
                    foreach ($y in $pair) {
                        #Write-Host $x $y
                        Write-Host Assigning Contributor Role for GPSUS-Group$x Account on Group$y Azure Resource
                        
                        Start-Job -ScriptBlock {
                            foreach ($rgsfx in $ResourceGroupSuffix) {
                                [void] (az role assignment create --assignee $accountId --role "Contributor" --resource-group $Prefix$y"-"$rgsfx)
                            }
                        }
                    }
                }
            
            }

        }
    }

    Write-Host "Script Ended"

}

###################################################################################################################################################
# Execution Examples:
###################################################################################################################################################

#Set-GroupAccountsPermissionsAndPasswords -NumberOfLabs even-number -CreateAccounts

Set-GroupAccountsPermissionsAndPasswords -Prefix "GPSUS-XYZ-" -PasswordPrefix "xyz" -NumberOfLabs even-number -CreateAccounts

#Set-GroupAccountsPermissionsAndPasswords -Prefix "GPSUS-XYZ-" -PasswordPrefix "xyz" -NumberOfLabs even-number -PasswordsOnly

Set-GroupAccountsPermissionsAndPasswords -NumberOfLabs even-number -DeleteAccounts

###################################################################################################################################################

# Delete Azure Resource Groups and their Resources

$prefix = "GPSUS-XYZ-"
$startFromLab = 1
$numberOfLabs = 6
for ($i = $startFromLab; $i -le $numberOfLabs; $i++) {
    az group delete --no-wait --yes --name $prefix$i-PrivateCloud
    az group delete --no-wait --yes --name $prefix$i-Operational
    az group delete --no-wait --yes --name $prefix$i-Network
    az group delete --no-wait --yes --name $prefix$i-Jumpbox --force-deletion-types Microsoft.Compute/virtualMachines

    Write-Host "Resources for $prefix$i deleted successfully"  -ForegroundColor Green
}

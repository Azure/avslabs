[void] (az login --identity)
[void] (az config set extension.use_dynamic_install=yes_without_prompt --only-show-errors)

$resourceGroup = az vmware private-cloud list --query [0].resourceGroup
$avsPrivateCloud = az vmware private-cloud list --query [0].name

$creds = az vmware private-cloud list-admin-credentials -c $avsPrivateCloud  -g $resourceGroup
$credsJson = $creds | ConvertFrom-Json

$endpoints = az vmware private-cloud show -n $avsPrivateCloud  -g $resourceGroup --query "endpoints"
$endpointsJson = $endpoints | ConvertFrom-Json

$nsxtURL = $endpointsJson.nsxtManager
$vcsaURL = $endpointsJson.vcsa

$vcsaIP = $vcsaURL.Substring(8)
$vcsaIP = $vcsaIP.Substring(0, $vcsaIP.Length - 1)

$nsxtIP = $nsxtURL.Substring(8)
$nsxtIP = $nsxtIP.Substring(0, $nsxtIP.Length - 1)

$AVSInfo = @{"AVSvCenter" = @{"IP" = $vcsaIP; "Username" = $credsJson.vcenterUsername; "Password" = $credsJson.vcenterPassword }; "AVSNSXT" = @{"IP" = $nsxtIP; "Username" = $credsJson.nsxtUsername; "Password" = $credsJson.nsxtPassword } }

#Run from PowerShell Core
.\labdeploy.ps1 -group 1 -lab 1 -automated -AVSInfo $AVSInfo
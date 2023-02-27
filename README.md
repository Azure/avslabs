# AVS LAB Automation

This repo has all necessary scripts and artifacts that you need to deploy AVS Lab with nested VMware-based environments.

> Nested virtualization is not supported by neither VMware nor Microsoft. It's used here for the sake of testing certain scenarios in Lab environment.

## Background
Deploying Azure VMware Solution (AVS) in Azure is feasible through multiple mechanisms (Portal/CLI/PowerShell). However, that alone is not enough to practice various exercises to become familiar with the service capabilities. There is a need for an on-premises VMware environment that has connectivity to the AVS private cloud. This, in fact, has been challenging to afford for the purpose of skilling as those resources typically cannot be provisioned on-demand for training or skilling purposes.

To address this issue, AVS Nested Labs has been introduced. It provides organizations and experts with a solution to overcome the challenge of not having an on-premises VMware-based environment for testing and skilling exercises to become more familiar with AVS. It is a fully-featured and isolated environment.

With AVS Nested Labs, you can set up a virtual environment that is similar to on-premises environment, without the need for physical hardware, and still be able to perform your tests and exercises in a safe and isolated environment.

Thus, the solution was to create automation package that will deploy AVS based on Enterprise Scale for Landing Zone templates and run PowerShell scripts that can provision **nested labs** within AVS Private Cloud to server the purpose of on-premises environment.


## Prerequisites

  1) Azure CLI: You can download it from [here](http://aka.ms/azurecli).
  2) AVS 3-Node Quota available in an Azure Subscription.

### Before you deploy
 
  1) Decide if you want to deploy a [single](./bicep/ESLZDeploy.Single.LAB.deploy.bicep) AVS Private Cloud (SDDC) , or [multiple](./bicep/ESLZDeploy.LAB.deploy.bicep) AVS Private Clouds.
  2) Review the parameters file, that corresponds to your deployment, to make sure you have the right parameters for the deployment. In other words, this depends if you are just deploying a single AVS Private Cloud (SDDC) or multiple ones.
  3) Based on your choice, you can use the instructions in the section below to kick-off the deployment.


## Deployment
Here are the steps you need to take to deploy AVS Lab with nested VMware lab environments.

>> Make sure to update the the parameter file with the right values, such as: **NumberOfAVSInstances**, **NumberOfNestedLabsInAVS**, **Prefix**, **Location**, **AlertEmails**, etc...

From Azure CLI run the deployment command as in the following example. Make sure to provide the a unique **name** for the deployment, the right **location**, your deployment choice **bicep file** and the corresponding **parameter file**.
```dotnetcli
az deployment sub create -n "<deployment-unique-name" -l "<location>" -f "<bicep-template-file-name>" -p "<corresponding-parameter-file>" --no-wait
```
As an example for **single lab** deployment:
```dotnetcli
az deployment sub create -n "AVS-LAB-2023-02-15" -l "brazilsouth" -f "ESLZDeploy.Single.LAB.deploy.bicep" -p "ESLZDeploy.Single.LAB.deploy.bicep.parameters.json" --no-wait
```
As an example for **multiple lab** deployment:
```dotnetcli
az deployment sub create -n "AVS-LAB-2023-02-15" -l "brazilsouth" -f "ESLZDeploy.LAB.deploy.bicep" -p "ESLZDeploy.LAB.deploy.bicep.parameters.json" --no-wait
```

For a reference to az deployment command, see [this](https://learn.microsoft.com/en-us/cli/azure/deployment/sub?view=azure-cli-latest#az-deployment-sub-create)



# Disclaimer

This is not official Microsoft documentation or software.
This is not an endorsement or a sign-off of an architecture or a design.
This code-sample is provided "AS IT IS" without warranty of any kind, either expressed or implied, including but not limited to the implied warranties of merchantability and/or fitness for a particular purpose.
This sample is not supported under any Microsoft standard support program or service.
Microsoft further disclaims all implied warranties, including, without limitation, any implied warranties of merchantability or fitness for a particular purpose.
The entire risk arising out of the use or performance of the sample and documentation remains with you.
In no event shall Microsoft, its authors, or anyone else involved in the creation, production, or delivery of the script be liable for any damages whatsoever (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or inability to use the sample or documentation, even if Microsoft has been advised of the possibility of such damages

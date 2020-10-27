<#
.SYNOPSIS
    Helper script to import complex variables into an automation account used by Azure Site Recovery
.DESCRIPTION
    This scripts is used to import complex variables into an automation account used by Azure Site Recovery.
.EXAMPLE
    PS C:\> .\Import-AutomationVariables.ps1 -AutomationAccountResourceGroupName rg-of-my-automation `
                                             -AutomationAccountName aut-myasr `
                                             -RecoveryVaultName rsv-supervault `
                                             -FabricLocation "East US 2" `
                                             -VariablesFileDefinitionPath /path/to/variablesdefinition.jsonc
.PARAMETER AutomationAccountResourceGroupName
    The automation account resource group name
.PARAMETER AutomationAccountName
    The automation account name
.PARAMETER RecoveryVaultName
    The Azure Site Recovery resource name
.PARAMETER FabricLocation
    The Region name of the fabric location where the protected items live
.PARAMETER VariablesFileDefinitionPath
    The path of the variables definition. This should be a json file
.INPUTS
    None 
.OUTPUTS
    None
.NOTES
    None
#>
[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true)]
    [string] $AutomationAccountResourceGroupName,
    [Parameter(Mandatory=$true)]
    [string] $AutomationAccountName,
    [Parameter(Mandatory=$true)]
    [string] $RecoveryVaultName,
    [Parameter(Mandatory=$true)]
    [string] $FabricLocation,
    [Parameter(Mandatory=$true)]
    [string] $VariablesFileDefinitionPath
)

$ErrorActionPreference = "stop"

function Convert-PSObjectToHashtable
{
    param (
        [Parameter(ValueFromPipeline)]
        $InputObject
    )

    process
    {
        if ($null -eq $InputObject) { return $null }

        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string])
        {
            $collection = @(
                foreach ($object in $InputObject) { Convert-PSObjectToHashtable $object }
            )

            $collection
        }
        elseif ($InputObject -is [psobject])
        {
            $hash = @{}

            foreach ($property in $InputObject.PSObject.Properties)
            {
                $hash[$property.Name] = Convert-PSObjectToHashtable $property.Value
            }

            $hash
        }
        else
        {
            $InputObject
        }
    }
}

$variablesDefinition = Get-Content -Path $VariablesFileDefinitionPath | ConvertFrom-Json | Convert-PSObjectToHashtable

$variable = Get-AzAutomationVariable -ResourceGroupName $AutomationAccountResourceGroupName -AutomationAccountName $AutomationAccountName -Name "VMManagedIdentities" -ErrorAction SilentlyContinue
$value = $variablesDefinition.vmManagedIdentities
$value.web.AsrVmIds = @()

$rsv = Get-AzRecoveryServicesVault -Name $RecoveryVaultName
Set-AzRecoveryServicesASRVaultContext -Vault $rsv
$fabricPrefix = $FabricLocation.Replace(" ","").ToLower()
$sourceFabric = Get-AzRecoveryServicesAsrFabric -Name "$fabricPrefix-fabric"
$sourceContainer = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $sourceFabric
$replicationProtectedItems = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $sourceContainer

foreach ($replicationProtectedItem in $replicationProtectedItems) {
	$vmId = $replicationProtectedItem.ProviderSpecificDetails.LifecycleId
	if ($replicationProtectedItem.FriendlyName -like "*web*")
	{
		$value.web.AsrVmIds += $vmId
	}
	else {
		Write-Warning "The protected item $($replicationProtectedItem.FriendlyName) doesn't match any conditions"
	}
}

if ($null -eq $variable) {
	New-AzAutomationVariable -ResourceGroupName $AutomationAccountResourceGroupName -AutomationAccountName $AutomationAccountName -Name "VMManagedIdentities" -Value $value -Encrypted $false
}
else {
	Set-AzAutomationVariable -ResourceGroupName $AutomationAccountResourceGroupName -AutomationAccountName $AutomationAccountName -Name "VMManagedIdentities" -Value $value -Encrypted $false
}
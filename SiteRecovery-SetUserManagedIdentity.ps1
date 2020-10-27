<#
.SYNOPSIS
    Sets the user managed identity on the failed over virtual machine
.DESCRIPTION
    This scripts is invoked by Azure Site Recovery to assign the user managed identity to the virtual machines it failed over
.PARAMETER RecoveryPlanContext
    The recovery plan context as passed by Azure Site Recovery. Azure Site Recovery passes it as a real PowerShell object. If you use the Azure Portal UI, it will be passed as a string 
.INPUTS
    None
.OUTPUTS
    None
.NOTES
    Depends on the Automation Account variable VMManagedIdentities
#>
[CmdLetBinding()]
Param (
    [Parameter(Mandatory=$True)]
    [Object] $RecoveryPlanContext
)

function Convert-JTokenToHashtable
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
            if (($PSVersionTable.PSVersion.Major -eq 5 -and $InputObject.GetType().FullName -eq "Newtonsoft.Json.Linq.JProperty") -or $InputObject -is [Newtonsoft.Json.Linq.JProperty]){
                $hash = @{}
                $hash[$InputObject.Name] = Convert-JTokenToHashtable $InputObject.Value
                $hash
            }
            elseif (($PSVersionTable.PSVersion.Major -eq 5 -and $InputObject.GetType().FullName -eq "Newtonsoft.Json.Linq.JObject") -or $InputObject -is [Newtonsoft.Json.Linq.JObject]) {
                $hash = @{}

                foreach ($object in $InputObject) {
                    $hash[$object.Name] = Convert-JTokenToHashtable $object.Value
                }

                $hash
            }
            elseif (($PSVersionTable.PSVersion.Major -eq 5 -and $InputObject.GetType().FullName -eq "Newtonsoft.Json.Linq.JArray") -or $InputObject -is [Newtonsoft.Json.Linq.JArray]) {

                $collection = @(
                    foreach ($object in $InputObject) { Convert-JTokenToHashtable $object }
                )

                $collection
            }
            else {
                $InputObject.Value
            }
        }
        elseif ($InputObject -is [psobject])
        {
            $hash = @{}

            foreach ($property in $InputObject.PSObject.Properties)
            {
                $hash[$property.Name] = Convert-JTokenToHashtable $property.Value
            }

            $hash
        }
        else
        {
            $InputObject
        }
    }
}

$ErrorActionPreference = "stop"

try {

    # Ensures that any credentials apply only to the execution of this runbook
    Disable-AzContextAutosave -Scope Process | Write-Verbose

    # Connect to Azure with RunAs account
    $servicePrincipalConnection = Get-AutomationConnection -Name AzureRunAsConnection

    $logonAttempt = 0
    $logonResult = $False

    while(!($connectionResult) -and ($logonAttempt -le 10)) {
        $LogonAttempt++
        # Logging in to Azure...
        Write-Output "Connecting to Azure..."
        $connectionResult = Connect-AzAccount `
                            -ServicePrincipal `
                            -TenantId $servicePrincipalConnection.TenantId `
                            -ApplicationId $servicePrincipalConnection.ApplicationId `
                            -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint

        if ($connectionResult) {
            $logonResult = $true
            break
        }
        Start-Sleep -Seconds 30
    }

    if ($logonResult -eq $false) {
        Write-Error -Message "Unable to sign in using the automation service principal account after 10 attempts"
        return
    }

    Write-Output "Connected to Azure"

    $vmManagedIdentitiesAutomationVar = Get-AutomationVariable -Name "VMManagedIdentities"
    $vmManagedIdentities = $vmManagedIdentitiesAutomationVar | Convert-JTokenToHashtable

    if ($RecoveryPlanContext.GetType().FullName -eq "System.String") {
        # the context is passed as a json string, such as in the automation account runbook UI
        $rpc = $RecoveryPlanContext | ConvertFrom-JSON
    }
    else {
        $rpc = $RecoveryPlanContext
    }

    $vmMap = $rpc.VmMap
    $vminfo = $vmMap | Get-Member | Where-Object MemberType -EQ NoteProperty | Select-Object -ExpandProperty Name
    foreach($vmId in $vminfo)
    {
        $VM = $vmMap.$vmId
        # This check is to ensure that we skip when some data is not available else it will fail
        if(!(($null -eq $VM) -or ($null -eq $VM.ResourceGroupName) -or ($null -eq $VM.RoleName))) {
            if ($vmManagedIdentities.web.AsrVmIds -contains $vmId) {
                if ($rpc.FailoverDirection -eq "PrimaryToSecondary") {
                    $identityName = $vmManagedIdentities.web.IdentityNameDR
                    $identityResourceGroupName = $vmManagedIdentities.web.ResourceGroupNameDR
                }
                else {
                    $identityName = $vmManagedIdentities.web.IdentityName
                    $identityResourceGroupName = $vmManagedIdentities.web.ResourceGroupName
                }
            }
            else {
                Write-Warning "$($vmId) [$($VM.ResourceGroupName)/$($VM.RoleName)] was not found in the automation configuration"
                continue
            }

            $azureVm = Get-AzVm -ResourceGroupName $VM.ResourceGroupName -Name $VM.RoleName
            $identity = Get-AzUserAssignedIdentity -ResourceGroupName $identityResourceGroupName -Name $identityName
            Write-Output "Setting identity $($identity.Name) to Virtual Machine $($VM.ResourceGroupName)/$($VM.RoleName)"
            Update-AzVM -VM $azureVm -ResourceGroupName $VM.ResourceGroupName -IdentityType UserAssigned -IdentityId $identity.Id
        }
        else {
            Write-Warning "$($vmId) - the recovery context vm has empty properties or is null itself"
        }
    }
}
catch {
    throw "An error occurred: $($_.Exception.Message)"
}
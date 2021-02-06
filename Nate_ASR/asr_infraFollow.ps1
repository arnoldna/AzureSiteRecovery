#
# PowerShell Asure Site Recovery Configuration 
#
#   Requirements:
#       1 - Recovery Serices Vault
#       2 - Virtual Networks. One in primary region and another in DR region
#       4 - Storage Accounts for Migration
#



# # Get details of the virtual machine
# $VM = Get-AzVM -ResourceGroupName "a2a-westu2-vm-rg" -Name "A2ADemo-VM"

# Write-Output $VM

# $OSDiskVhdURI = $VM.StorageProfile.OsDisk.Vhd
# $DataDisk1VhdURI = $VM.StorageProfile.DataDisks[0].Vhd

New-AzResourceGroup -Name "a2a-westus-rsv-rg" -Location "West US" -Tag @{Environment="ASR"; Failover="RSV"}
#Create a new Recovery services vault in the recovery region
$vault = New-AzRecoveryServicesVault -Name "a2a-RecoveryVault-1" -ResourceGroupName "a2a-westus-rsv-rg" -Location "West US"

Write-Output $vault

#Setting the vault context.
Set-AzRecoveryServicesAsrVaultContext -Vault $vault

#Set the vault context for the PowerShell session.
Set-AzRecoveryServicesAsrVaultContext -Vault $vault

#Create Primary ASR fabric
$TempASRJob = New-AzRecoveryServicesAsrFabric -Azure -Location 'WestUS2' -Name "A2A-WestUS2-Fabric"

# Track Job status to check for completion
while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted")){
        #If the job hasn't completed, Start-Sleep for 10 seconds before checking the job status again
        Start-Sleep 10;
        $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob
}

#Check if the Job completed successfully. The updated job state of a successfully completed job should be "Succeeded"
Write-Output $TempASRJob.State

$PrimaryFabric = Get-AzRecoveryServicesAsrFabric -Name "A2A-WestUS2-Fabric"

########################################
#Create Recovery ASR fabric
########################################
$TempASRJob = New-AzRecoveryServicesAsrFabric -Azure -Location 'WestUS'  -Name "A2A-WestUS-Fabric"

# Track Job status to check for completion
while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted")){
        Start-Sleep 10;
        $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob
}

#Check if the Job completed successfully. The updated job state of a successfully completed job should be "Succeeded"
Write-Output $TempASRJob.State

$RecoveryFabric = Get-AzRecoveryServicesAsrFabric -Name "A2A-WestUS-Fabric"

#Create a Protection container in the primary Azure region (within the Primary fabric)
$TempASRJob = New-AzRecoveryServicesAsrProtectionContainer -InputObject $PrimaryFabric -Name "A2A-WestUS2-ProtectionContainer"

#Track Job status to check for completion
while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted")){
        Start-Sleep 10;
        $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob
}

Write-Output $TempASRJob.State

$PrimaryProtContainer = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $PrimaryFabric -Name "A2A-WestUS2-ProtectionContainer"


#Create a Protection container in the recovery Azure region (within the Recovery fabric)
$TempASRJob = New-AzRecoveryServicesAsrProtectionContainer -InputObject $RecoveryFabric -Name "A2A-WestUS-ProtectionContainer"

#Track Job status to check for completion
while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted")){
        Start-Sleep 10;
        $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob
}

#Check if the Job completed successfully. The updated job state of a successfully completed job should be "Succeeded"

Write-Output $TempASRJob.State

$RecoveryProtContainer = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $RecoveryFabric -Name "A2A-WestUS-ProtectionContainer"


#Create replication policy
$TempASRJob = New-AzRecoveryServicesAsrPolicy -AzureToAzure -Name "A2A-Policy" -RecoveryPointRetentionInHours 24 -ApplicationConsistentSnapshotFrequencyInHours 4

#Track Job status to check for completion
while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted")){
        Start-Sleep 10;
        $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob
}

#Check if the Job completed successfully. The updated job state of a successfully completed job should be "Succeeded"
Write-Output $TempASRJob.State

$ReplicationPolicy = Get-AzRecoveryServicesAsrPolicy -Name "A2A-Policy"

#Create Protection container mapping between the Primary and Recovery Protection Containers with the Replication policy
$TempASRJob = New-AzRecoveryServicesAsrProtectionContainerMapping -Name "A2A-Primary-To-Recovery" -Policy $ReplicationPolicy -PrimaryProtectionContainer $PrimaryProtContainer -RecoveryProtectionContainer $RecoveryProtContainer

#Track Job status to check for completion
while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted")){
        Start-Sleep 10;
        $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob
}

#Check if the Job completed successfully. The updated job state of a successfully completed job should be "Succeeded"
Write-Output $TempASRJob.State

$Wus2ToWusPCMapping = Get-AzRecoveryServicesAsrProtectionContainerMapping -ProtectionContainer $PrimaryProtContainer -Name "A2A-Primary-To-Recovery"

#Create Protection container mapping (for fail back) between the Recovery and Primary Protection Containers with the Replication policy
$TempASRJob = New-AzRecoveryServicesAsrProtectionContainerMapping -Name "A2A-Recovery-To-Primary" -Policy $ReplicationPolicy -PrimaryProtectionContainer $RecoveryProtContainer -RecoveryProtectionContainer $PrimaryProtContainer

#Track Job status to check for completion
while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted")){
        Start-Sleep 10;
        $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob
}

#Check if the Job completed successfully. The updated job state of a successfully completed job should be "Succeeded"
Write-Output $TempASRJob.State

$WusToWus2PCMapping = Get-AzRecoveryServicesAsrProtectionContainerMapping -ProtectionContainer $RecoveryProtContainer -Name "A2A-Recovery-To-Primary"

###########################################
# Storage Accounts
##########################################

# Create Cache Storage accounts in Each region. One for initial failover in the primary region and one for failback in the failover region

# New Resoruce Group for Cache Storage Primary
New-AzResourceGroup -Name "A2A-WestUS2-Cache-SA-RG" -Location "WestUS2" -Tag @{Environment="ASR"; Primary="Cache Storage Location"}

#Create Cache storage account for replication logs in the primary region
$WestUS2CacheStorageAccount = New-AzStorageAccount -Name "a2acachestoragewus2" -ResourceGroupName "A2A-WestUS2-Cache-SA-RG" -Location 'WestUS2' -SkuName Standard_LRS -Kind Storage

# New Resoruce Group for Cache Storage Failover
New-AzResourceGroup -Name "A2A-WestUS-Cache-SA-RG" -Location "WestUS" -Tag @{Environment="ASR"; Recovery="Cache Storage Location"}

#Create Cache storage account for replication logs in the primary region
$WestUSCacheStorageAccount = New-AzStorageAccount -Name "a2acachestoragewus" -ResourceGroupName "A2A-WestUS-Cache-SA-RG" -Location 'WestUS' -SkuName Standard_LRS -Kind Storage

###################################################
# Create Target Storage accounts in Each region. One for initial failover in the failover region and one for failback in the primary region
###################################################

# New Resoruce Group for Target Storage Primary
New-AzResourceGroup -Name "A2A-WestUS2-Target-SA-RG" -Location "WestUS2" -Tag @{Environment="ASR"; Primary="Target Storage Location"}

#Create Target storage account in the primary region. In this case a Standard Storage account
$WestUS2TargetStorageAccount = New-AzStorageAccount -Name "a2atargetstoragewus2" -ResourceGroupName "A2A-WestUS2-Target-SA-RG" -Location 'West US 2' -SkuName Standard_LRS -Kind Storage

# New Resource Group for Target Storage Recovery
New-AzResourceGroup -Name "A2A-WestUS-Target-SA-RG" -Location "WestUS" -Tag @{Environment="ASR"; Recovery="Target Storage Location"}

#Create Target storage account in the recovery region. In this case a Standard Storage account
$WestUSTargetStorageAccount = New-AzStorageAccount -Name "a2atargetstoragewus" -ResourceGroupName "a2a-WestUS-target-sa-rg" -Location 'West US' -SkuName Standard_LRS -Kind Storage


##################################################
# Networking
##################################################

#Create a Recovery Network in the recovery region
New-AzResourceGroup -Name "a2a-WestUS-failover-vnet-rg" -Location "WestUS2"
$WestUSRecoveryVnet = New-AzVirtualNetwork -Name "a2a-WestUS-failover-vnet" -ResourceGroupName "a2a-WestUS-failover-vnet-rg" -Location 'West US' -AddressPrefix "10.0.0.0/16"

Add-AzVirtualNetworkSubnetConfig -Name "default" -VirtualNetwork $WestUSRecoveryVnet -AddressPrefix "10.0.0.0/20" | Set-AzVirtualNetwork

$WestUSRecoveryNetwork = $WestUSRecoveryVnet.Id

#############################
# Network for VM
#############################
#Retrieve the virtual network that the virtual machine is connected to

  #Get first network interface card(nic) of the virtual machine
  $SplitNicArmId = $VM.NetworkProfile.NetworkInterfaces[0].Id.split("/")

  #Extract resource group name from the ResourceId of the nic
  $NICRG = $SplitNicArmId[4]

  #Extract resource name from the ResourceId of the nic
  $NICname = $SplitNicArmId[-1]

  #Get network interface details using the extracted resource group name and resource name
  $NIC = Get-AzNetworkInterface -ResourceGroupName $NICRG -Name $NICname

  #Get the subnet ID of the subnet that the nic is connected to
  $PrimarySubnet = $NIC.IpConfigurations[0].Subnet

  # Extract the resource ID of the Azure virtual network the nic is connected to from the subnet ID
  $WestUS2PrimaryNetwork = (Split-Path(Split-Path($PrimarySubnet.Id))).Replace("\","/")


##########################################
# Network Mapping for ASR
##########################################

#Create an ASR network mapping between the primary Azure virtual network and the recovery Azure virtual network
$TempASRJob = New-AzRecoveryServicesAsrNetworkMapping -AzureToAzure -Name "A2AWus2ToWusNWMapping" -PrimaryFabric $PrimaryFabric -PrimaryAzureNetworkId $WestUS2PrimaryNetwork -RecoveryFabric $RecoveryFabric -RecoveryAzureNetworkId $WestUSRecoveryNetwork

#Track Job status to check for completion
while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted")){
        Start-Sleep 10;
        $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob
}

#Check if the Job completed successfully. The updated job state of a successfully completed job should be "Succeeded"
Write-Output $TempASRJob.State

#Create an ASR network mapping for fail back between the recovery Azure virtual network and the primary Azure virtual network
$TempASRJob = New-AzRecoveryServicesAsrNetworkMapping -AzureToAzure -Name "A2A-Wus-To-Wus2-NWMapping" -PrimaryFabric $RecoveryFabric -PrimaryAzureNetworkId $WestUSRecoveryNetwork -RecoveryFabric $PrimaryFabric -RecoveryAzureNetworkId $WestUS2PrimaryNetwork

#Track Job status to check for completion
while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted")){
        Start-Sleep 10;
        $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TempASRJob
}

#Check if the Job completed successfully. The updated job state of a successfully completed job should be "Succeeded"
Write-Output $TempASRJob.State


########################################################

#Get the resource group that the virtual machine must be created in when failed over.
New-AzResourceGroup -Name "a2a-westu-vm-rg" -Location "West US"
$RecoveryRG = Get-AzResourceGroup -Name "a2a-westu-vm-rg" -Location "West US"

#Specify replication properties for each disk of the VM that is to be replicated (create disk replication configuration)

#OsDisk
$OSdiskId = $vm.StorageProfile.OsDisk.ManagedDisk.Id
$RecoveryOSDiskAccountType = $vm.StorageProfile.OsDisk.ManagedDisk.StorageAccountType
$RecoveryReplicaDiskAccountType = $vm.StorageProfile.OsDisk.ManagedDisk.StorageAccountType

$OSDiskReplicationConfig = New-AzRecoveryServicesAsrAzureToAzureDiskReplicationConfig -ManagedDisk -LogStorageAccountId $WestUS2CacheStorageAccount.Id `
         -DiskId $OSdiskId -RecoveryResourceGroupId  $RecoveryRG.ResourceId -RecoveryReplicaDiskAccountType  $RecoveryReplicaDiskAccountType `
         -RecoveryTargetDiskAccountType $RecoveryOSDiskAccountType

# Data disk
$datadiskId1 = $vm.StorageProfile.DataDisks[0].ManagedDisk.Id
$RecoveryReplicaDiskAccountType = $vm.StorageProfile.DataDisks[0].ManagedDisk.StorageAccountType
$RecoveryTargetDiskAccountType = $vm.StorageProfile.DataDisks[0].ManagedDisk.StorageAccountType

$DataDisk1ReplicationConfig  = New-AzRecoveryServicesAsrAzureToAzureDiskReplicationConfig -ManagedDisk -LogStorageAccountId $WestUS2CacheStorageAccount.Id `
         -DiskId $datadiskId1 -RecoveryResourceGroupId $RecoveryRG.ResourceId -RecoveryReplicaDiskAccountType $RecoveryReplicaDiskAccountType `
         -RecoveryTargetDiskAccountType $RecoveryTargetDiskAccountType

#Create a list of disk replication configuration objects for the disks of the virtual machine that are to be replicated.
$diskconfigs = @()
$diskconfigs += $OSDiskReplicationConfig, $DataDisk1ReplicationConfig

#Start replication by creating replication protected item. Using a GUID for the name of the replication protected item to ensure uniqueness of name.
$TempASRJob = New-AzRecoveryServicesAsrReplicationProtectedItem -AzureToAzure -AzureVmId $VM.Id -Name (New-Guid).Guid -ProtectionContainerMapping $Wus2ToWusPCMapping -AzureToAzureDiskReplicationConfiguration $diskconfigs -RecoveryResourceGroupId $RecoveryRG.ResourceId

# Check the Replication State
Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $PrimaryProtContainer | Select-Object FriendlyName, ProtectionState, ReplicationHealth

# Test Network for failover

#Create a separate network for test failover (not connected to my DR network)
$TFOVnet = New-AzVirtualNetwork -Name "a2aTFOvnet" -ResourceGroupName "a2a-demo-rsv-rg" -Location 'West US 2' -AddressPrefix "10.3.0.0/16"

Add-AzVirtualNetworkSubnetConfig -Name "default" -VirtualNetwork $TFOVnet -AddressPrefix "10.3.0.0/20" | Set-AzVirtualNetwork

$TFONetwork = $TFOVnet.Id


##################################
# Test Failover
##################################
$ReplicationProtectedItem = Get-AzRecoveryServicesAsrReplicationProtectedItem -FriendlyName "Nate-VM" -ProtectionContainer $PrimaryProtContainer

$TFOJob = Start-AzRecoveryServicesAsrTestFailoverJob -ReplicationProtectedItem $ReplicationProtectedItem -AzureVMNetworkId $TFONetwork -Direction PrimaryToRecovery

##################################
# Test Failover Status
##################################
Get-AzRecoveryServicesAsrJob -Job $TFOJob | Select State

##################################
# Clean-Up Test Failover
##################################
$Job_TFOCleanup = Start-AzRecoveryServicesAsrTestFailoverCleanupJob -ReplicationProtectedItem $ReplicationProtectedItem

##################################
# Clean-Up Test Failover Status
##################################
Get-AzRecoveryServicesAsrJob -Job $Job_TFOCleanup | Select State

##################################
# Real VM Failover
#
# First step is to get recovery points
##################################
$RecoveryPoints = Get-AzRecoveryServicesAsrRecoveryPoint -ReplicationProtectedItem $ReplicationProtectedItem

#The list of recovery points returned may not be sorted chronologically and will need to be sorted first, in order to be able to find the oldest or the latest recovery points for the virtual machine.
"{0} {1}" -f $RecoveryPoints[0].RecoveryPointType, $RecoveryPoints[-1].RecoveryPointTime

##################################
# Real VM Failover Status
##################################

#Start the fail over job
$Job_Failover = Start-AzRecoveryServicesAsrUnplannedFailoverJob -ReplicationProtectedItem $ReplicationProtectedItem -Direction PrimaryToRecovery -RecoveryPoint $RecoveryPoints[-1]

do {
    $Job_Failover = Get-AzRecoveryServicesAsrJob -Job $Job_Failover;
    Start-Sleep 30;
} while (($Job_Failover.State -eq "InProgress") -or ($JobFailover.State -eq "NotStarted"))

$Job_Failover.State

##################################
# Commit the VM Failover
##################################
$CommitFailoverJOb = Start-AzRecoveryServicesAsrCommitFailoverJob -ReplicationProtectedItem $ReplicationProtectedItem

Get-AzRecoveryServicesAsrJob -Job $CommitFailoverJOb

###########################################
# Reprotect and failover to source region
###########################################
#Create Cache storage account for replication logs in the primary region
$WestUSCacheStorageAccount = New-AzStorageAccount -Name "a2acachestoragewestus" -ResourceGroupName $RecoveryRG -Location 'West US' -SkuName Standard_LRS -Kind Storage


$sourceVMResourcegroup = get-azresourceGroup -name "a2a-demo-rsv-rg"
#Use the recovery protection container, new cache storage account in West US and the source region VM resource group
$UpdateProtectionDirection = Update-AzRecoveryServicesAsrProtectionDirection -ReplicationProtectedItem $ReplicationProtectedItem -AzureToAzure -ProtectionContainerMapping $WusToEusPCMapping -LogStorageAccountId $WestUSCacheStorageAccount.Id -RecoveryResourceGroupID $sourceVMResourcegroup.ResourceId


Get-AzRecoveryServicesAsrJob -Job $UpdateProtectionDirection
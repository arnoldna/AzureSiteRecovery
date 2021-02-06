$PrimaryFabric = Get-AzRecoveryServicesAsrFabric -Name "A2Ademo-EastUS"
$ProtectedItem = "Nate-VM"
$PrimaryProtContainer = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $PrimaryFabric -Name "A2AEastUSProtectionContainer"
##################################
# Test Failover
##################################
$ReplicationProtectedItem = Get-AzRecoveryServicesAsrReplicationProtectedItem -FriendlyName "Nate-VM" -ProtectionContainer $PrimaryProtContainer

$TFOJob = Start-AzRecoveryServicesAsrTestFailoverJob -ReplicationProtectedItem $ReplicationProtectedItem -AzureVMNetworkId $TFONetwork -Direction PrimaryToRecovery

##################################
# Test Failover Status
##################################

while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted")){
    sleep 10;
    $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $TFOJob
}


##################################
# Clean-Up Test Failover
##################################
$Job_TFOCleanup = Start-AzRecoveryServicesAsrTestFailoverCleanupJob -ReplicationProtectedItem $ReplicationProtectedItem

##################################
# Clean-Up Test Failover Status
##################################

while (($TempASRJob.State -eq "InProgress") -or ($TempASRJob.State -eq "NotStarted")){
    sleep 10;
    $TempASRJob = Get-AzRecoveryServicesAsrJob -Job $Job_TFOCleanup
}

$Nodes = @("A2019-N01","B2019-N01")

Test-Cluster

New-Cluster `
  -Name POCCLUSTER01 `
  -Node A2019-N01,B2019-N01 `
  -StaticAddress 10.10.11.101,192.168.10.101 `
  -NoStorage

  #Test-NetConnection A2019-N01 -Port 3343
Test-NetConnection B2019-N01 -Port 3343

Set-ClusterQuorum `
    -FileShareWitness "\\POCFile\Witness$"


    #Move-ClusterGroup "Cluster Group" -Node B2019-N01


    Get-ClusterResource | Set-ClusterParameter RegisterAllProvidersIP 1

Get-ClusterResource | Set-ClusterParameter HostRecordTTL 300

Stop-ClusterResource
Start-ClusterResource 

$Net = Get-ClusterNetwork | Where-Object {$_.Address -eq "192.168.15.0"}

#$NewName =

$Net.Address 

$Prefix = ($Net.Address -split '\.')[0..2] -join '.'

$Net.Name = "Heartbeat-$Prefix"
$Net.Role = 1

#(Get-ClusterNetwork | Where-Object {$_.Address -eq "192.168.0.0"}).Name = "Heartbeat"
#(Get-ClusterNetwork | Where-Object {$_.Address -eq "192.168.0.0"}).Role = 1
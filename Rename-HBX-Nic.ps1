#Rename NSX Heartbeat
$HBXDNS = ($cs = Get-CimInstance Win32_ComputerSystem).DNSHostName  + '-HBX' + '.' + $cs.Domain
$HBXIP = (Resolve-DnsName $HBXDNS).IPAddress

$NewNicName = "X-HeartBeat"

$OldHeartBeat = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object {$_.IPAddress -eq $HBXIP}).InterfaceAlias

# Find adapter that is not currently connected to the production network
# Adjust filter if required
$Adapter = Get-NetAdapter |
    Where-Object Status -eq Up |
    Where-Object Name -match "$OldHeartBeat"

if (-not $Adapter) {
    throw "Additonal Heartbeat adapter not found"
}

# Rename adapter
Rename-NetAdapter -Name $Adapter.Name -NewName $NewNicName
$HBXDNS = ($cs = Get-CimInstance Win32_ComputerSystem).DNSHostName  + '-HBX' + '.' + $cs.Domain
$HBXIP = (Resolve-DnsName $HBXDNS).IPAddress
$HBXPrefix = ($HBXIP -split '\.')[0..2] -join '.'

$HBXNet = Get-ClusterNetwork | Where-Object {$_.Address -match $HBXPrefix}

$HBXNet.Address 

$HBXPrefix = ($HBXNet.Address -split '\.')[0..2] -join '.'

$HBXNet.Name = "Heartbeat-$HBXPrefix"
$HBXNet.Role = 1
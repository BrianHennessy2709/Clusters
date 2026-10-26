$HBDNS = ($cs = Get-CimInstance Win32_ComputerSystem).DNSHostName  + '-HB' + '.' + $cs.Domain
$HBIP = (Resolve-DnsName $HBDNS).IPAddress
$HBPrefix = ($HBIP -split '\.')[0..2] -join '.'

$HBNet = Get-ClusterNetwork | Where-Object {$_.Address -match $HBPrefix}

$HBNet.Address 

$HBPrefix = ($HBNet.Address -split '\.')[0..2] -join '.'

$HBNet.Name = "Heartbeat-$HBPrefix"
$HBNet.Role = 1



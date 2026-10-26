$HBXDNS = ($cs = Get-CimInstance Win32_ComputerSystem).DNSHostName  + '-HBX' + '.' + $cs.Domain
$HBXIP = (Resolve-DnsName $HBXDNS).IPAddress

$OldHeartBeat = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object {$_.IPAddress -eq $HBXIP}).InterfaceAlias


    Disable-NetAdapter -Name $OldHeartBeat -Confirm:$false
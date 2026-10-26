$HBXDNS = ($cs = Get-CimInstance Win32_ComputerSystem).DNSHostName  + '-HB' + '.' + $cs.Domain
$HBXIP = (Resolve-DnsName $HBXDNS).IPAddress

$OldHeartBeat = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object {$_.IPAddress -eq $HBXIP}).InterfaceAlias


    Enable-NetAdapter -Name $OldHeartBeat -Confirm:$false
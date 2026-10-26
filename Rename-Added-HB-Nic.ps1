$NewNicName = "HeartBeat"

# Heartbeat DNS name based on computer name
$HBName = "$($env:COMPUTERNAME)-HB"

# Resolve heartbeat DNS record
$HBIP = (Resolve-DnsName $HBName -Type A -ErrorAction Stop).IPAddress

# Find adapter that is not currently connected to the production network
# Adjust filter if required
$Adapter = Get-NetAdapter |
    Where-Object Status -eq Up |
    Where-Object Name -notmatch "Team|Prod|Management|Data|HeartBeat"

if (-not $Adapter) {
    Write-Host "Additonal Heartbeat adapter not found"
}

else{

# Rename adapter
Rename-NetAdapter -Name $Adapter.Name -NewName $NewNicName

# Remove existing IPv4 addresses
Get-NetIPAddress -InterfaceAlias $NewNicName -AddressFamily IPv4 |
    Where-Object PrefixOrigin -ne "WellKnown" |
    Remove-NetIPAddress -Confirm:$false

# Apply address
New-NetIPAddress `
    -InterfaceAlias $NewNicName `
    -IPAddress $HBIP `
    -PrefixLength 24

# No gateway on heartbeat network - TEST THIS

Get-NetRoute -InterfaceAlias $NewNicName -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Remove-NetRoute -Confirm:$false

New-NetRoute -DestinationPrefix "192.168.15.0/24" -NextHop "192.168.16.254" -InterfaceAlias $NewNicName

# Disable DNS registration
Set-DnsClient `
    -InterfaceAlias $NewNicName `
    -RegisterThisConnectionsAddress $false

Write-Host "New-Heartbeat configured as $HBIP"
    }

#New-NetRoute -DestinationPrefix "192.168.15.0/24" -NextHop "192.168.16.254" -InterfaceAlias "HeartBeat"

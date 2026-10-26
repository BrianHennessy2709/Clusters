
$Destination = "192.168.15.0/24"
$Gateway = "192.168.16.254"
$Interface = "Heartbeat"

# Check if the route already exists
if (Get-NetRoute -DestinationPrefix $Destination -NextHop $Gateway -ErrorAction SilentlyContinue) {
    Write-Host "Route to $Destination via $Gateway already exists." -ForegroundColor Yellow
} else {
    # Add the route if it is missing
    New-NetRoute -DestinationPrefix $Destination -NextHop $Gateway -InterfaceAlias $Interface
    Write-Host "Route to $Destination successfully added." -ForegroundColor Green
}



#New-NetRoute -DestinationPrefix "192.168.15.0/24" -NextHop "192.168.16.254" -InterfaceAlias "HeartBeat"
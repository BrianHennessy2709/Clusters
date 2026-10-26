$DisbledHeartBeat = (Get-NetAdapter | Where-Object { $_.Status -ne "Up" -and $_.Name -eq "X-HeartBeat" }).Name

Enable-NetAdapter -Name $DisbledHeartBeat -Confirm:$false
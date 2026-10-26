function SetXHeartBeatNICName {

    $FunctionName = $MyInvocation.MyCommand
    Write-Host "Starting $FunctionName"

    #Set the Name for the Cross-Site Stetched Network
    $NewNicName = "X-HeartBeat"

    #Construct Heartbeat FQDN & Check DNS Entry
    $HBXDNS = ($cs = Get-CimInstance Win32_ComputerSystem).DNSHostName  + '-HBX' + '.' + $cs.Domain

    #Validate DNS Entry
    $HBXIP = (Resolve-DnsName $HBXDNS -ErrorAction SilentlyContinue).IPAddress
        
        if($HBXIP -eq $null){
                            Write-Host "HBX DNS Record does not exist for $env:COMPUTERNAME"
                            EXIT 9991
                            }
        else{
            Write-Host "HBX DNS Record for $env:COMPUTERNAME = $HBXIP"
            Write-Host "Getting current Heartbeat Adapter Name"

            $OldHeartBeat = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -eq $HBXIP}).InterfaceAlias

            if($OldHeartBeat -eq $null){Write-Host "No Adapter configured with HBX DNS IP Address"}

            else{

            Write-Host "Current HBX Adater name is $OldHeartBeat"
            # Find adapter 
            $Adapter = Get-NetAdapter | Where-Object Status -eq Up | Where-Object Name -match "$OldHeartBeat"

                 if (-not $Adapter) {

                        Write-Host "Heartbeat Adapter not found on $env:COMPUTERNAME"
                        exiT 9992
                    }
                else{

                    # Rename adapter

                    try {
                        Write-Host "Ranaming Adapter to $NewNicName"
                        Rename-NetAdapter -Name $Adapter.Name -NewName $NewNicName
                        }

                    catch{
                        $_.ExceptionError
                        }
                    }
                }
            }

    Write-Host "Finished $FunctionName"
    
}

SetXHeartBeatNICName
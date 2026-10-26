function SetXHeartBeatNICName {

    [CmdletBinding(SupportsShouldProcess)]
    param()

    $FunctionName = $MyInvocation.MyCommand
    Write-Host "Starting $FunctionName"

    # Set the Name for the Cross-Site Stretched Network
    $NewNicName = "X-HeartBeat"

    # Prevent duplicate target adapter names
    $ExistingAdapter = Get-NetAdapter -Name $NewNicName -ErrorAction SilentlyContinue

    if ($ExistingAdapter) {
        Write-Host "Adapter already exists with name '$NewNicName'."
        EXIT 9993
    }

    # Construct Heartbeat FQDN & Check DNS Entry
    $HBXDNS = ($cs = Get-CimInstance Win32_ComputerSystem).DNSHostName + '-HBX' + '.' + $cs.Domain

    # Validate DNS Entry
    $HBXIP = (Resolve-DnsName $HBXDNS -ErrorAction SilentlyContinue).IPAddress

    if ($HBXIP -eq $null) {

        Write-Host "HBX DNS Record does not exist for $env:COMPUTERNAME"
        EXIT 9991

    }
    else {

        Write-Host "HBX DNS Record for $env:COMPUTERNAME = $HBXIP"
        Write-Host "Getting current Heartbeat Adapter Name"

        # Find adapters using the HBX IP
        $IPMatches = Get-NetIPAddress -AddressFamily IPv4 |
                     Where-Object { $_.IPAddress -eq $HBXIP }

        if (($IPMatches | Measure-Object).Count -eq 0) {

            Write-Host "No Adapter configured with HBX DNS IP Address"
            EXIT 9994

        }

        if (($IPMatches | Measure-Object).Count -gt 1) {

            Write-Host "Multiple adapters found using HBX IP Address [$HBXIP]. Aborting."

            $IPMatches |
                Select-Object InterfaceAlias, IPAddress |
                Format-Table -AutoSize

            EXIT 9995
        }

        $OldHeartBeat = $IPMatches.InterfaceAlias

        Write-Host "Current HBX Adapter name is $OldHeartBeat"

        # Exact name match rather than regex match
        $Adapter = Get-NetAdapter |
                   Where-Object {
                        $_.Status -eq 'Up' -and
                        $_.Name -eq $OldHeartBeat
                   }

        if (-not $Adapter) {

            Write-Host "Heartbeat Adapter not found on $env:COMPUTERNAME"
            EXIT 9992

        }

        # Protection against multiple adapter matches
        if (($Adapter | Measure-Object).Count -gt 1) {

            Write-Host "Multiple adapters matched interface alias '$OldHeartBeat'."
            EXIT 9996

        }

        # Detect already-configured adapter
        if ($Adapter.Name -eq $NewNicName) {

            Write-Host "Adapter already named '$NewNicName'. No action required."
            EXIT 0

        }

        try {

            if ($PSCmdlet.ShouldProcess($Adapter.Name, "Rename adapter to $NewNicName")) {

                Write-Host "Renaming Adapter to $NewNicName"

                Rename-NetAdapter `
                    -Name $Adapter.Name `
                    -NewName $NewNicName `
                    -ErrorAction Stop
            }
        }
        catch {

            Write-Host $_.Exception.Message
            EXIT 9997
        }
    }

    Write-Host "Finished $FunctionName"
}


SetXHeartBeatNICName
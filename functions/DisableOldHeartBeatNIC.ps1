function DisableOldHeartBeatNIC {

    [CmdletBinding(SupportsShouldProcess)]
    param()

    $FunctionName = $MyInvocation.MyCommand
    Write-Host "Starting $FunctionName"

    try {

        #
        # Resolve legacy heartbeat address
        #
        $cs = Get-CimInstance Win32_ComputerSystem

        $HBXDNS = "$($cs.DNSHostName)-HBX.$($cs.Domain)"

        try {
            $HBXIP = (Resolve-DnsName $HBXDNS -ErrorAction Stop).IPAddress
        }
        catch {
            Write-Host "Failed to resolve DNS name: $HBXDNS"
            EXIT 9991
        }

        Write-Host "Heartbeat-X IP: $HBXIP"

        #
        # Locate adapter hosting the legacy HBX address
        #
        $Adapters = Get-NetIPAddress `
            -AddressFamily IPv4 `
            -ErrorAction Stop |
            Where-Object {
                $_.IPAddress -eq $HBXIP
            }

        if (-not $Adapters) {
            Write-Host "No adapter found with IP address $HBXIP"
            EXIT 9992
        }

        if (($Adapters | Measure-Object).Count -gt 1) {
            Write-Host "Multiple adapters found with IP address $HBXIP"
            $Adapters |
                Select-Object InterfaceAlias, IPAddress |
                Format-Table -AutoSize

            EXIT 9993
        }

        $OldHeartBeat = $Adapters.InterfaceAlias

        Write-Host "Legacy heartbeat adapter found: $OldHeartBeat"

        #
        # Safety check
        #
        $Adapter = Get-NetAdapter `
            -Name $OldHeartBeat `
            -ErrorAction Stop

        if ($Adapter.Status -eq 'Disabled') {
            Write-Host "Adapter $OldHeartBeat is already disabled"
            EXIT 9994
        }

        #
        # Disable adapter
        #
        if ($PSCmdlet.ShouldProcess($OldHeartBeat, "Disable legacy heartbeat adapter")) {

            Disable-NetAdapter `
                -Name $OldHeartBeat `
                -Confirm:$false `
                -ErrorAction Stop

            Write-Host "Disabled adapter: $OldHeartBeat"
        }

        Write-Host "Finished $FunctionName"
    }
    catch {
        Write-Host "Function failed"
        Write-Host "Exception : $($_.Exception.Message)"
        Write-Host "Line      : $($_.InvocationInfo.ScriptLineNumber)"
        Write-Host "Statement : $($_.InvocationInfo.Line.Trim())"
        EXIT 9999
    }
}

DisableOldHeartBeatNIC
function SetHeartBeatNIC {

    [CmdletBinding(SupportsShouldProcess)]
    param()

    $FunctionName = $MyInvocation.MyCommand
    Write-Host "Starting $FunctionName"

    $NewNicName = "HeartBeat"

    #
    # Validate target adapter name is not already in use
    #
    $ExistingAdapter = Get-NetAdapter -Name $NewNicName -ErrorAction SilentlyContinue

    if ($ExistingAdapter) {
        Write-Host "Adapter '$NewNicName' already exists."
        EXIT 9991
    }

    #
    # Heartbeat DNS record
    #
    $HBName = "$($env:COMPUTERNAME)-HB"

    try {
        $HBIP = (Resolve-DnsName $HBName -Type A -ErrorAction Stop).IPAddress
    }
    catch {
        Write-Host "Failed to resolve DNS name: $HBName"
        EXIT 9992
    }

    

    Write-Host "Heartbeat DNS IP: $HBIP"

    #
    # Find candidate adapter
    #
    $Adapters = Get-NetAdapter |
        Where-Object Status -eq Up |
        Where-Object Name -notmatch 'Team|Prod|Management|Data|HeartBeat'

    if (-not $Adapters) {
        Write-Host "Additional Heartbeat adapter not found"
        EXIT 9995
    }

    if (($Adapters | Measure-Object).Count -gt 1) {

        Write-Host "Multiple possible heartbeat adapters found. Aborting."

        $Adapters |
            Select-Object Name, InterfaceDescription |
            Format-Table -AutoSize

        EXIT 9996
    }

    $Adapter = $Adapters[0]

    Write-Host "Selected adapter: $($Adapter.Name)"

    #
    # Verify adapter does not already contain HB IP
    #
    $ExistingIP = Get-NetIPAddress `
        -InterfaceIndex $Adapter.ifIndex `
        -AddressFamily IPv4 `
        -ErrorAction SilentlyContinue |
        Where-Object IPAddress -eq $HBIP

    if ($ExistingIP) {
        Write-Host "Adapter already configured with heartbeat IP $HBIP"
        EXIT 9997
    }

    if ($PSCmdlet.ShouldProcess($Adapter.Name, "Configure Heartbeat NIC")) {

        try {

            #
            # Rename adapter
            #
            Rename-NetAdapter `
                -Name $Adapter.Name `
                -NewName $NewNicName `
                -ErrorAction Stop

            #
            # Remove existing IPv4 addresses
            #
            try {
                $StaticIPs = Get-NetIPAddress `
                    -InterfaceAlias $NewNicName `
                    -AddressFamily IPv4 `
                    -ErrorAction Stop |
                Where-Object {
                    $_.PrefixOrigin -eq 'Manual'
                }
            }
            catch {
                Write-Verbose "No IPv4 addresses found on adapter '$NewNicName'"
                $StaticIPs = @()
            }

            if ($StaticIPs.Count -gt 0) {
                $StaticIPs | Remove-NetIPAddress -Confirm:$false
            }

            #
            # Apply address
            #
            New-NetIPAddress `
                -InterfaceAlias $NewNicName `
                -IPAddress $HBIP `
                -PrefixLength 24

            #
            # Remove routes
            #
            #Get-NetRoute `
            #    -InterfaceAlias $NewNicName `
            #    -AddressFamily IPv4 `
            #    -ErrorAction SilentlyContinue |
            #Remove-NetRoute -Confirm:$false

            #
            # Apply static route
            #
            #New-NetRoute `
            #    -DestinationPrefix "192.168.15.0/24" `
            #    -NextHop "192.168.16.254" `
            #    -InterfaceAlias $NewNicName
            #$LocalNode = $env:COMPUTERNAME

            #$RemoteNode = (Get-ClusterNode | Where-Object Name -ne $LocalNode).Name

            #$RemoteHBIP = (Resolve-DnsName "$RemoteNode-HB").IPAddress
            #$LocalHBIP = (Resolve-DnsName "$LocalNode-HB").IPAddress

            #$RemoteGatewayIP = ($RemoteHBIP -replace '\d+$','254')
            #$LocalGatewayIP = ($LocalHBIP -replace '\d+$','254')

            #$DestPrefix = ($RemoteHBIP -replace '\d+$','0')

            #New-NetRoute `
            #    -DestinationPrefix "$DestPrefix/24" `
            #    -NextHop $LocalGatewayIP `
            #    -InterfaceAlias $NewNicName

            #
            # Disable DNS registration
            #
            Set-DnsClient `
                -InterfaceAlias $NewNicName `
                -RegisterThisConnectionsAddress $false

            Write-Host "Heartbeat configured as $HBIP"
        }
        catch {
            Write-Host $_.Exception.Message
            EXIT 9998
        }
    }

    Write-Host "Finished $FunctionName"
}


SetHeartBeatNIC
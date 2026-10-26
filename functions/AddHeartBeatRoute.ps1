function AddHeartBeatRoute {

    [CmdletBinding(SupportsShouldProcess)]
    param()

    $FunctionName = $MyInvocation.MyCommand
    Write-Host "Starting $FunctionName"

    try {

        #
        # Validate cluster membership
        #
        try {
            $null = Get-Cluster -ErrorAction Stop
        }
        catch {
            Write-Host "This server is not a cluster node."
            EXIT 9991
        }

        #
        # Validate heartbeat adapter exists
        #
        $NewNicName = "HeartBeat"

        $Adapter = Get-NetAdapter `
            -Name $NewNicName `
            -ErrorAction SilentlyContinue

        if (-not $Adapter) {
            Write-Host "Adapter '$NewNicName' not found."
            EXIT 9992
        }

        #
        # Determine local and remote nodes
        #
        $LocalNode = $env:COMPUTERNAME

        $RemoteNode = (Get-ClusterNode |
            Where-Object Name -ne $LocalNode).Name

        if (-not $RemoteNode) {
            Write-Host "Unable to identify remote cluster node."
            EXIT 9993
        }

        #
        # Resolve heartbeat DNS records
        #
        try {
            $RemoteHBIP = (Resolve-DnsName "$RemoteNode-HB" -ErrorAction Stop).IPAddress
            $LocalHBIP  = (Resolve-DnsName "$LocalNode-HB"  -ErrorAction Stop).IPAddress
        }
        catch {
            Write-Host "Failed to resolve heartbeat DNS records."
            EXIT 9994
        }

        #
        # Build route information
        #
        $RemoteGatewayIP = ($RemoteHBIP -replace '\d+$','254')
        $LocalGatewayIP  = ($LocalHBIP  -replace '\d+$','254')

        $DestPrefix = ($RemoteHBIP -replace '\d+$','0')

        Write-Host "Remote Heartbeat IP : $RemoteHBIP"
        Write-Host "Local Heartbeat IP  : $LocalHBIP"
        Write-Host "Destination Prefix  : $DestPrefix/24"
        Write-Host "Next Hop            : $LocalGatewayIP"

        #
        # Check for existing route
        #
        $ExistingRoute = Get-NetRoute `
            -DestinationPrefix "$DestPrefix/24" `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.NextHop -eq $LocalGatewayIP
            }

        if ($ExistingRoute) {
            Write-Host "Route already exists."
            EXIT 9995
        }

        #
        # Create route
        #
        if ($PSCmdlet.ShouldProcess($NewNicName, "Add heartbeat route")) {

            New-NetRoute `
                -DestinationPrefix "$DestPrefix/24" `
                -NextHop $LocalGatewayIP `
                -InterfaceAlias $NewNicName `
                -ErrorAction Stop

            Write-Host "Route added successfully."
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

AddHeartBeatRoute
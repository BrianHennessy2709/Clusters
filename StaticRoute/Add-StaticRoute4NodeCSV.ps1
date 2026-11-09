function Add-HeartBeatRoute {

    <#
    .SYNOPSIS
    Creates a static route between cluster heartbeat networks.

    .DESCRIPTION
    Uses cluster node information and DNS records to
    calculate the required route and creates a persistent
    heartbeat route on the HeartBeat adapter.

    .PARAMETER None
    This function does not accept parameters.

    .EXAMPLE
    AddHeartBeatRoute

    Creates a route to the remote heartbeat network.

    #>

    [CmdletBinding(SupportsShouldProcess)]
    param()

    $FunctionName = $MyInvocation.MyCommand
    Write-Log "Starting $FunctionName"

    $CsvPath = "C:\Temp\HeartBeatNetworks.csv"
    $RouteNetworks = Import-Csv $CsvPath

    try {

        #
        # Validate cluster membership
        #
        try {
            $null = Get-Cluster -ErrorAction Stop
        }
        catch {
            Write-Log -Severity Error "This server is not a cluster node."
            Write-Log "Finished $FunctionName"
            return
        }

        #
        # Validate heartbeat adapter exists
        #
        $NewNicName = "HeartBeat"

        $Adapter = Get-NetAdapter `
            -Name $NewNicName `
            -ErrorAction SilentlyContinue

        if (-not $Adapter) {
            Write-Log -Severity Error "Adapter '$NewNicName' not found."
            Write-Log "Finished $FunctionName"
            return
        }

        #
        # Determine local and remote nodes
        #
        $SiteA = 'N01','N02'
        $SiteB = 'N03','N04'

        $LocalNode = $env:COMPUTERNAME

        $NodeSuffix = $LocalNode.Substring($LocalNode.Length - 3)

        if ($NodeSuffix -in $SiteA)
        {
            $SameSiteNodes = (Get-ClusterNode).Name | Where-Object {
                $_ -match 'N01|N02' -and $_ -ne $LocalNode
            }

            $RemoteSiteNodes = (Get-ClusterNode).Name | Where-Object {
                $_ -match 'N03|N04'
            }
        }
        else
        {
            $SameSiteNodes = (Get-ClusterNode).Name | Where-Object {
                $_ -match 'N03|N04' -and $_ -ne $LocalNode
            }

            $RemoteSiteNodes = (Get-ClusterNode).Name | Where-Object {
                $_ -match 'N01|N02'
            }
        }

        $RemoteNode = $RemoteSiteNodes | Select-Object -First 1

        if (-not $RemoteNode) {
            Write-Log -Severity Error "Unable to identify remote cluster node."
            Write-Log "Finished $FunctionName"
            return
        }

        #
        # Resolve heartbeat DNS records
        #
        try {
            $RemoteHBIP = (Resolve-DnsName "$RemoteNode-HB" -ErrorAction Stop).IPAddress
            $LocalHBIP  = (Resolve-DnsName "$LocalNode-HB" -ErrorAction Stop).IPAddress
        }
        catch {
            Write-Log -Severity Error "Failed to resolve heartbeat DNS records."
            Write-Log "Finished $FunctionName"
            return
        }

        #
        # Build route information from CSV
        #
        $RouteConfig = $RouteNetworks | Where-Object {
            $NetworkPrefix = ($_.Network -split '\.')[0..2] -join '.'
            $RemoteHBIP -like "$NetworkPrefix.*"
        } | Select-Object -First 1

        if (-not $RouteConfig) {
            Write-Log -Severity Error "No matching route configuration found for $RemoteHBIP"
            Write-Log "Finished $FunctionName"
            return
        }

        $PrefixLength = switch ($RouteConfig.SubnetMask)
        {
            '255.255.254.0'   { 23 }
            '255.255.255.0'   { 24 }
            '255.255.255.128' { 25 }
            '255.255.255.192' { 26 }
            '255.255.255.224' { 27 }
            '255.255.255.240' { 28 }
            '255.255.255.248' { 29 }
            '255.255.255.252' { 30 }
            default { throw "Unsupported subnet mask $($RouteConfig.SubnetMask)" }
        }

        $DestPrefix = "$($RouteConfig.Network)/$PrefixLength"
        $LocalGatewayIP = $RouteConfig.Gateway

        Write-Log "Remote Heartbeat IP : $RemoteHBIP"
        Write-Log "Local Heartbeat IP  : $LocalHBIP"
        Write-Log "Destination Prefix  : $DestPrefix"
        Write-Log "Next Hop            : $LocalGatewayIP"

        #
        # Check for existing route
        #
        $ExistingRoute = Get-NetRoute `
            -DestinationPrefix $DestPrefix `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.NextHop -eq $LocalGatewayIP
            }

        if ($ExistingRoute) {
            Write-Log -Severity Error "Route already exists."
            Write-Log "Finished $FunctionName"
            return
        }

        #
        # Create route
        #
        if ($PSCmdlet.ShouldProcess($NewNicName, "Add heartbeat route")) {

            New-NetRoute `
                -DestinationPrefix $DestPrefix `
                -NextHop $LocalGatewayIP `
                -InterfaceAlias $NewNicName `
                -ErrorAction Stop

            Write-Log "Route added successfully."
        }

        Write-Log "Finished $FunctionName"
    }
    catch {
        Write-Log -Severity Error "Function failed"
        Write-Log -Severity Error "Exception : $($_.Exception.Message)"
        Write-Log -Severity Error "Line      : $($_.InvocationInfo.ScriptLineNumber)"
        Write-Log -Severity Error "Statement : $($_.InvocationInfo.Line.Trim())"
        Write-Log -Severity Error "Finished $FunctionName"
        return
    }

    Write-Log "Finished $FunctionName"
}

Add-HeartBeatRoute
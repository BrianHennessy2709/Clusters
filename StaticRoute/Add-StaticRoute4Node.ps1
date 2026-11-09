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

    $CsvPath = "C:\Temp\HeartBeatNetworks.CSV"
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
            $LocalHBIP  = (Resolve-DnsName "$LocalNode-HB"  -ErrorAction Stop).IPAddress
        }
        catch {
            Write-Log -Severity Error "Failed to resolve heartbeat DNS records."
            Write-Log "Finished $FunctionName"
            return
        }

        #
        # Build route information
        #
        $RemoteGatewayIP = ($RemoteHBIP -replace '\d+$','254')
        $LocalGatewayIP  = ($LocalHBIP  -replace '\d+$','254')

        $DestPrefix = ($RemoteHBIP -replace '\d+$','0')

        Write-Log "Remote Heartbeat IP : $RemoteHBIP"
        Write-Log "Local Heartbeat IP  : $LocalHBIP"
        Write-Log "Destination Prefix  : $DestPrefix/24"
        Write-Log "Next Hop            : $LocalGatewayIP"

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
            Write-Log -Severity Error "Route already exists."
            Write-Log "Finished $FunctionName"
            return
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

            Write-Log "Route added successfully."
        }

        Write-Log "Finished $FunctionName"
    }
    catch {
        Write-Log -Severity Error "Function failed"
        Write-Log -Severity Error  "Exception : $($_.Exception.Message)"
        Write-Log -Severity Error  "Line      : $($_.InvocationInfo.ScriptLineNumber)"
        Write-Log -Severity Error "Statement : $($_.InvocationInfo.Line.Trim())"
        Write-Log -Severity Error "Finished $FunctionName"
        return
    }
    Write-Log "Finished $FunctionName"
}

Add-HeartBeatRoute
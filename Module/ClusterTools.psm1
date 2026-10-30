<#
.FILENAME

.DESCRIPTION

.CHANGE HISTORY
    VERSION |DATE   |AUTHOR |DETAILS
    

#>

<#
.EXITCODES TABLE

Code    Function                      Description
----    --------                      -----------
9001    Export-ClusterBaseline        Server is not a cluster node
9002    Export-ClusterBaseline        Failed to create output folder
9099    Export-ClusterBaseline        Unexpected error

9101    SetXHeartBeatNICName          HBX DNS record not found
9102    SetXHeartBeatNICName          Heartbeat adapter not found
9103    SetXHeartBeatNICName          Target adapter name already exists
9104    SetXHeartBeatNICName          No adapter using HBX IP address
9105    SetXHeartBeatNICName          Multiple adapters using HBX IP address
9106    SetXHeartBeatNICName          Multiple adapter alias matches found
9199    SetXHeartBeatNICName          Unexpected error

9201    SetHeartBeatNIC              HeartBeat adapter name already exists
9202    SetHeartBeatNIC              Failed to resolve HeartBeat DNS record
9203    SetHeartBeatNIC              No candidate adapter found
9204    SetHeartBeatNIC              Multiple candidate adapters found
9205    SetHeartBeatNIC              Adapter already configured with HeartBeat IP
9299    SetHeartBeatNIC              Unexpected error

9301    Set-HeartbeatClusterNetwork  Cluster service not found
9302    Set-HeartbeatClusterNetwork  Cluster service not running
9303    Set-HeartbeatClusterNetwork  Unable to connect to cluster
9304    Set-HeartbeatClusterNetwork  Failed to resolve HeartBeat DNS record
9305    Set-HeartbeatClusterNetwork  No matching cluster network found
9306    Set-HeartbeatClusterNetwork  Multiple matching cluster networks found
9307    Set-HeartbeatClusterNetwork  Subnet validation failed
9308    Set-HeartbeatClusterNetwork  Network already configured
9399    Set-HeartbeatClusterNetwork  Unexpected error

9401    AddHeartBeatRoute            Server is not a cluster node
9402    AddHeartBeatRoute            HeartBeat adapter not found
9403    AddHeartBeatRoute            Unable to identify remote node
9404    AddHeartBeatRoute            Failed to resolve DNS records
9405    AddHeartBeatRoute            Route already exists
9499    AddHeartBeatRoute            Unexpected error

9501    Test-HeartBeatDNS            DNS resolution failed
9502    Test-HeartBeatDNS            Ping test failed
9503    Test-HeartBeatDNS            One or more validation tests failed
9599    Test-HeartBeatDNS            Unexpected error

9601    DisableOldHeartBeatNIC       Failed to resolve HBX DNS record
9602    DisableOldHeartBeatNIC       No adapter found using HBX IP
9603    DisableOldHeartBeatNIC       Multiple adapters found using HBX IP
9604    DisableOldHeartBeatNIC       Adapter already disabled
9699    DisableOldHeartBeatNIC       Unexpected error

9701    EnableOldHeartBeatNIC        Disabled adapter not found
9702    EnableOldHeartBeatNIC        Multiple matching adapters found
9703    EnableOldHeartBeatNIC        Adapter already enabled
9799    EnableOldHeartBeatNIC        Unexpected error

9900    Common                       General validation error
9999    Common                       Unhandled exception
#>

function Export-ClusterBaseline {

    <#
    .SYNOPSIS
    Exports a baseline configuration snapshot of a Windows Server Failover Cluster node.

    .DESCRIPTION
    Collects operating system, network, DNS and cluster configuration
    information and exports the results to timestamped files for
    documentation, troubleshooting or rollback validation.

    .PARAMETER OutputPath
    Root folder used to store the generated baseline collection.

    .EXAMPLE
    Export-ClusterBaseline

    Exports baseline information to C:\Windows\Build.

    .EXAMPLE
    Export-ClusterBaseline -OutputPath D:\Baseline

    Exports baseline information to D:\Baseline.

    #>

    [CmdletBinding()]
    param(
        [string]$OutputPath = "C:\Windows\Build"
    )
    if (-not (Test-Path -Path $OutputPath)) {
            New-Item -ItemType Directory -Path "C:\Windows\Build" | Out-Null
            Write-Log "$OutputPath did not exist and has been created."
    } 
    else {
        Write-Log "$OutputPath already exists. No action taken."
    }
    $FunctionName = $MyInvocation.MyCommand
    Write-Log "Starting $FunctionName"

    try {
        $null = Get-Cluster -ErrorAction Stop
    }
    catch {
        Write-Log "Finished $FunctionName"
        throw "This server is not a Failover Cluster node. $($_.Exception.Message)"
    }

    $TimeStamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $Folder = Join-Path $OutputPath "ClusterBaseline_$TimeStamp"

    New-Item -Path $Folder -ItemType Directory -Force | Out-Null

    Write-Log "Exporting baseline to $Folder"

    #
    # Operating System & Cluster Service
    #
    Get-ComputerInfo |
        Out-File "$Folder\ComputerInfo.txt"

    Get-Service ClusSvc |
        Format-List * |
        Out-File "$Folder\ClusterService.txt"

    #
    # Network Configuration
    #
    Get-NetAdapter |
        Select-Object Name,
                      InterfaceDescription,
                      ifIndex,
                      Status,
                      MacAddress,
                      LinkSpeed |
        Export-Csv "$Folder\NetworkAdapters.csv" -NoTypeInformation

    Get-NetIPAddress |
        Select-Object IPAddress,
                      InterfaceIndex,
                      InterfaceAlias,
                      AddressFamily,
                      Type,
                      PrefixLength |
        Export-Csv "$Folder\IPAddresses.csv" -NoTypeInformation

    Get-NetIPConfiguration |
        Select-Object InterfaceAlias,
                      InterfaceIndex,
                      InterfaceDescription,
                      @{N='NetworkCategory';E={$_.NetProfile.NetworkCategory}},
                      @{N='IPv4Address';E={$_.IPv4Address.IPAddress -join ';'}},
                      @{N='IPv4Gateway';E={$_.IPv4DefaultGateway.NextHop}},
                      @{N='DnsServers';E={$_.DNSServer.ServerAddresses -join ';'}} |
        Export-Csv "$Folder\IPConfiguration.csv" -NoTypeInformation

    Get-NetRoute |
        Select-Object ifIndex,
                      DestinationPrefix,
                      NextHop,
                      RouteMetric,
                      ifMetric,
                      PolicyStore |
        Export-Csv "$Folder\Routes.csv" -NoTypeInformation

    Get-NetIPInterface |
        Where-Object AddressFamily -eq IPv4 |
        Select-Object ifIndex,
                      InterfaceAlias,
                      AddressFamily,
                      NlMtu,
                      InterfaceMetric,
                      Dhcp,
                      ConnectionState,
                      PolicyStore |
        Export-Csv "$Folder\IPInterfaces.csv" -NoTypeInformation

    Get-NetAdapterAdvancedProperty |
        Select-Object Name,
                      DisplayName,
                      DisplayValue |
        Export-Csv "$Folder\AdapterAdvancedProperties.csv" -NoTypeInformation

    #
    # Cluster Configuration
    #
    Get-Cluster |
        Format-List * |
        Out-File "$Folder\Cluster.txt"

    Get-ClusterNode |
        Select-Object Name,
                      Id,
                      State |
        Export-Csv "$Folder\ClusterNodes.csv" -NoTypeInformation

    Get-ClusterNetwork |
        Select-Object Name,
                      Address,
                      AddressMask,
                      Role,
                      Metric,
                      AutoMetric,
                      State |
        Export-Csv "$Folder\ClusterNetworks.csv" -NoTypeInformation

    Get-ClusterNetworkInterface |
        Select-Object Node,
                      Network,
                      IPAddress,
                      State,
                      Adapter |
        Export-Csv "$Folder\ClusterNetworkInterfaces.csv" -NoTypeInformation

    Get-ClusterGroup |
        Select-Object Name,
                      OwnerNode,
                      State |
        Export-Csv "$Folder\ClusterGroups.csv" -NoTypeInformation

    Get-ClusterResource |
        Select-Object Name,
                      ResourceType,
                      OwnerGroup,
                      OwnerNode,
                      State |
        Export-Csv "$Folder\ClusterResources.csv" -NoTypeInformation

    Get-ClusterQuorum |
        Format-List * |
        Out-File "$Folder\ClusterQuorum.txt"

    #
    # DNS Validation
    #
    $CS = Get-CimInstance Win32_ComputerSystem

    $Records = @(
        "$($CS.DNSHostName).$($CS.Domain)"
        "$($CS.DNSHostName)-HB.$($CS.Domain)"
        "$($CS.DNSHostName)-HBX.$($CS.Domain)"
    )

    foreach ($Record in $Records) {

        $SafeName = ($Record -replace '[\\/:*?"<>|]', '_').Replace('.', '_')

        try {
            Resolve-DnsName $Record -ErrorAction Stop |
                Select-Object Name,
                              Type,
                              IPAddress |
                Export-Csv "$Folder\$SafeName.csv" -NoTypeInformation
        }
        catch {
            [PSCustomObject]@{
                Name   = $Record
                Result = "Failed to Resolve"
                Error  = $_.Exception.Message
            } |
            Export-Csv "$Folder\$SafeName.csv" -NoTypeInformation
        }
    }

    Write-Log "Baseline export complete."
    Write-Log "Output folder: $Folder"
}

function Set-XHeartBeatNICName {

    <#
    .SYNOPSIS
    Renames the adapter associated with the HeartBeat-X DNS record.

    .DESCRIPTION
    Resolves the host HBX DNS record, identifies the adapter configured
    with the returned IP address and renames the adapter to X-HeartBeat.

    .PARAMETER None
    This function does not accept parameters.

    .EXAMPLE
    SetXHeartBeatNICName

    Renames the detected HBX adapter to X-HeartBeat.

    #>

    [CmdletBinding(SupportsShouldProcess)]
    param()

    $FunctionName = $MyInvocation.MyCommand    
    Write-Log "Starting $FunctionName"

    # Set the Name for the Cross-Site Stretched Network
    $NewNicName = "X-HeartBeat"

    # Prevent duplicate target adapter names
    $ExistingAdapter = Get-NetAdapter -Name $NewNicName -ErrorAction SilentlyContinue

    if ($ExistingAdapter) {        
        Write-Log "Adapter already exists with name '$NewNicName'."
        Write-Log "Finished $FunctionName"
        EXIT 9103
    }

    # Construct Heartbeat FQDN & Check DNS Entry
    $HBXDNS = ($cs = Get-CimInstance Win32_ComputerSystem).DNSHostName + '-HBX' + '.' + $cs.Domain

    # Validate DNS Entry
    $HBXIP = (Resolve-DnsName $HBXDNS -ErrorAction SilentlyContinue).IPAddress

    if ($HBXIP -eq $null) {

        Write-Log "HBX DNS Record does not exist for $env:COMPUTERNAME"
        Write-Log "Finished $FunctionName"
        EXIT 9101

    }
    else {

        Write-Log "HBX DNS Record for $env:COMPUTERNAME = $HBXIP"        
        Write-Log "Getting current Heartbeat Adapter Name"

        # Find adapters using the HBX IP
        $IPMatches = Get-NetIPAddress -AddressFamily IPv4 |
                     Where-Object { $_.IPAddress -eq $HBXIP }

        if (($IPMatches | Measure-Object).Count -eq 0) {

            Write-Log "No Adapter configured with HBX DNS IP Address"
            Write-Log "Finished $FunctionName"
            EXIT 9104

        }

        if (($IPMatches | Measure-Object).Count -gt 1) {

            Write-Log "Multiple adapters found using HBX IP Address [$HBXIP]. Aborting."

            $IPMatches |
                Select-Object InterfaceAlias, IPAddress |
                Format-Table -AutoSize

            Write-Log "Finished $FunctionName"
            EXIT 9105
        }

        $OldHeartBeat = $IPMatches.InterfaceAlias

        Write-Log "Current HBX Adapter name is $OldHeartBeat"

        # Exact name match rather than regex match
        $Adapter = Get-NetAdapter |
                   Where-Object {
                        $_.Status -eq 'Up' -and
                        $_.Name -eq $OldHeartBeat
                   }

        if (-not $Adapter) {

            Write-Log "Heartbeat Adapter not found on $env:COMPUTERNAME"
            Write-Log "Finished $FunctionName"
            EXIT 9102

        }

        # Protection against multiple adapter matches
        if (($Adapter | Measure-Object).Count -gt 1) {

            Write-Log "Multiple adapters matched interface alias '$OldHeartBeat'."
            Write-Log "Finished $FunctionName"
            EXIT 9106

        }

        # Detect already-configured adapter
        if ($Adapter.Name -eq $NewNicName) {

            Write-Log "Adapter already named '$NewNicName'. No action required."
            Write-Log "Finished $FunctionName"
            EXIT 0

        }
        else{
        try {

            if ($PSCmdlet.ShouldProcess($Adapter.Name, "Rename adapter to $NewNicName")) {

                Write-Log "Renaming Adapter to $NewNicName"

                Rename-NetAdapter `
                    -Name $Adapter.Name `
                    -NewName $NewNicName `
                    -ErrorAction Stop
            }
        }
        catch {

            Write-Log $_.Exception.Message
            Write-Log "Finished $FunctionName"
            EXIT 9199
        }
        }
    }
    Write-Log "Finished $FunctionName"
}

function Set-HeartBeatNIC {

    <#
    .SYNOPSIS
    Configures the HeartBeat network adapter.

    .DESCRIPTION
    Locates an unassigned adapter, renames it to HeartBeat,
    configures the IP address from DNS and disables DNS
    registration on the adapter.

    .PARAMETER None
    This function does not accept parameters.

    .EXAMPLE
    SetHeartBeatNIC

    Configures the heartbeat network adapter using the
    DNS record COMPUTERNAME-HB.

    #>

    [CmdletBinding(SupportsShouldProcess)]
    param()

    $FunctionName = $MyInvocation.MyCommand
    Write-Log "Starting $FunctionName"

    $NewNicName = "HeartBeat"

    #
    # Validate target adapter name is not already in use
    #
    $ExistingAdapter = Get-NetAdapter -Name $NewNicName -ErrorAction SilentlyContinue

    if ($ExistingAdapter) {
        Write-Log "Adapter '$NewNicName' already exists."
        Write-Log -Severity Warning "Finished $FunctionName"
        EXIT 9201
    }

    #
    # Heartbeat DNS record
    #
    $HBName = "$($env:COMPUTERNAME)-HB"

    try {
        $HBIP = (Resolve-DnsName $HBName -Type A -ErrorAction Stop).IPAddress
    }
    catch {
        Write-Log -Severity Error "Failed to resolve DNS name: $HBName"
        Write-Log "Finished $FunctionName"
        EXIT 9202
    }

    

    Write-Log "Heartbeat DNS IP: $HBIP"

    #
    # Find candidate adapter
    #
    $Adapters = Get-NetAdapter |
        Where-Object Status -eq Up |
        Where-Object Name -notmatch 'Team|Prod|Management|Data|HeartBeat'

    if (-not $Adapters) {
        Write-Log -Severity Error "Additional Heartbeat adapter not found"
        Write-Log "Finished $FunctionName"
        EXIT 9203
    }

    if (($Adapters | Measure-Object).Count -gt 1) {

        Write-Log -Severity Error "Multiple possible heartbeat adapters found. Aborting."

        $Adapters |
            Select-Object Name, InterfaceDescription |
            Format-Table -AutoSize
         Write-Log "Finished $FunctionName"
        EXIT 9204
    }

    $Adapter = $Adapters[0]

    Write-Log "Selected adapter: $($Adapter.Name)"

    #
    # Verify adapter does not already contain HB IP
    #
    $ExistingIP = Get-NetIPAddress `
        -InterfaceIndex $Adapter.ifIndex `
        -AddressFamily IPv4 `
        -ErrorAction SilentlyContinue |
        Where-Object IPAddress -eq $HBIP

    if ($ExistingIP) {
        Write-Log -Severity Error "Adapter already configured with heartbeat IP $HBIP"
        Write-Log "Finished $FunctionName"
        EXIT 9205
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

            Set-DnsClient `
                -InterfaceAlias $NewNicName `
                -RegisterThisConnectionsAddress $false

            Write-Log "Heartbeat configured as $HBIP"
        }
        catch {
            Write-Log -Severity Error $_.Exception.Message
             Write-Log -ErrorVariable Error  "Finished $FunctionName"
            EXIT 9299
        }
    }

    Write-Log "Finished $FunctionName"
}

function Set-HeartbeatClusterNetwork {

    <#
    .SYNOPSIS
    Configures the Failover Cluster heartbeat network.

    .DESCRIPTION
    Identifies the cluster network matching the HeartBeat
    DNS subnet and updates the network name and role
    within the cluster configuration.

    .PARAMETER None
    This function does not accept parameters.

    .EXAMPLE
    Set-HeartbeatClusterNetwork

    Renames the matching cluster network and sets the
    cluster network role to Internal Cluster Communications.

    #>

    [CmdletBinding(SupportsShouldProcess)]
    param()
    $FunctionName = $MyInvocation.MyCommand
    Write-Log "Starting $FunctionName"

    # Verify Cluster Service exists and is running
    $ClusterService = Get-Service -Name ClusSvc -ErrorAction SilentlyContinue

    if (-not $ClusterService) {
        Write-Log -Severity Error "Cluster Service (ClusSvc) not found on this server."
        Write-Log "Finished $FunctionName"
        return
    }

    if ($ClusterService.Status -ne 'Running') {
        Write-Log -Severity Error "Cluster Service is not running. Current state: $($ClusterService.Status)"
        Write-Log "Finished $FunctionName"
        return
    }

    # Verify cluster connectivity
    try {
        $Cluster = Get-Cluster -ErrorAction Stop
    }
    catch {
        Write-Log -Severity Error "Unable to communicate with the failover cluster."
         Write-Log "Finished $FunctionName"
        return
    }

    Write-Log "Connected to cluster: $($Cluster.Name)"

    #Add wait to allow the Cluster Network to create
    Write-Log "Waiting for Cluster Network"
    Start-Sleep -Seconds 10
    
    # Build expected heartbeat DNS record
    $CS = Get-CimInstance Win32_ComputerSystem
    $HBDNS = "$($CS.DNSHostName)-HB.$($CS.Domain)"

    Write-Log "Resolving heartbeat DNS record: $HBDNS"

    try {
        $HBIP = (Resolve-DnsName $HBDNS -ErrorAction Stop |
            Where-Object {$_.Type -eq 'A'} |
            Select-Object -ExpandProperty IPAddress -First 1)
    }
    catch {
        Write-Log -Severity Error "Failed to resolve $HBDNS"
        Write-Log "Finished $FunctionName"
        return
    }

    if (-not $HBIP) {
        Write-Log -Severity Error "No IPv4 address returned from DNS."
        Write-Log "Finished $FunctionName"
        return
    }

    Write-Log "Heartbeat IP: $HBIP"

    # Build subnet prefix
    $HBPrefix = ($HBIP -split '\.')[0..2] -join '.'

    Write-Log "Expected subnet prefix: $HBPrefix"

    # Find matching cluster networks
    $Matches = Get-ClusterNetwork | Where-Object {
        $_.Address -like "$HBPrefix*"
    }

    if ($Matches.Count -eq 0) {
        Write-Log -Severity Error "No cluster network found matching subnet prefix $HBPrefix"
        Write-Log "Finished $FunctionName"
        return
    }

    if ($Matches.Count -gt 1) {
        Write-Log -Severity Error "Multiple cluster networks match subnet prefix $HBPrefix. Aborting."

        $Matches |
            Select-Object Name, Address, Role |
            Format-Table -AutoSize

            Write-Log "Finished $FunctionName"

        return
    }

    $HBNet = $Matches[0]

    # Additional subnet validation
    $NetworkPrefix = ($HBNet.Address -split '\.')[0..2] -join '.'

    if ($NetworkPrefix -ne $HBPrefix) {
        Write-Log -Severity Error @"
Subnet validation failed.

DNS subnet     : $HBPrefix
Cluster subnet : $NetworkPrefix

No changes made.
"@
        Write-Log "Finished $FunctionName"
        return
    }

    # Prevent renaming an already configured network
    #if ($HBNet.Name -notmatch '^Cluster Network') {
    if ($HBNet.Name -eq "Heartbeat-$HBPrefix") {

        Write-Log -Severity Warning "Matched network is already named:$($HBNet.Name):Aborting to prevent accidental modification."
        Write-Log "Finished $FunctionName"

        return
    }

    
    Write-Log "Validation Summary"
    Write-Log "------------------"
    Write-Log "Cluster       : $($Cluster.Name)"
    Write-Log "DNS Record    : $HBDNS"
    Write-Log "Heartbeat IP  : $HBIP"
    Write-Log "Network Name  : $($HBNet.Name)"
    Write-Log "Network Addr  : $($HBNet.Address)"
    Write-Log "Current Role  : $($HBNet.Role)"
    Write-Log "New Name      : Heartbeat-$HBPrefix"
    Write-Log "New Role      : 1"
    

    if ($PSCmdlet.ShouldProcess($HBNet.Name, "Rename network and set Role=1")) {

        $HBNet.Name = "Heartbeat-$HBPrefix"
        $HBNet.Role = 1

       
        Write-Log "Successfully updated cluster network."
        Write-Log "Name : $($HBNet.Name)"
    }
    Write-Log "Finished $FunctionName"
}

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
            EXIT 9401
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
            EXIT 9402
        }

        #
        # Determine local and remote nodes
        #
        $LocalNode = $env:COMPUTERNAME

        $RemoteNode = (Get-ClusterNode |
            Where-Object Name -ne $LocalNode).Name

        if (-not $RemoteNode) {
            Write-Log -Severity Error "Unable to identify remote cluster node."
            Write-Log "Finished $FunctionName"
            EXIT 9403
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
            EXIT 9404
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
            EXIT 9405
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
        EXIT 9499
    }
    Write-Log "Finished $FunctionName"
}

function Write-Log {

    <#
    .SYNOPSIS
    Writes log entries to screen and file.

    .DESCRIPTION
    Creates timestamped log entries and records them to a text
    log file while also displaying coloured console output.

    .PARAMETER Message
    Message to record.

    .PARAMETER Severity
    Log severity level.

    .PARAMETER LogFile
    Destination log file.

    .EXAMPLE
    Write-Log -Message "Starting validation"

    .EXAMPLE
    Write-Log -Message "DNS lookup failed" -Severity Error

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Information','Warning','Error')]
        [string]$Severity = 'Information',

        [string]$LogFile = 'C:\Windows\Build\ClusterHeartBeatScript.log'
    )

    $Date   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $Server = $env:COMPUTERNAME

    $LogEntry = "$Date`t$Server`t$Severity`t$Message"

    switch ($Severity) {
        'Information' { Write-Host $LogEntry -ForegroundColor Green }
        'Warning'     { Write-Host $LogEntry -ForegroundColor Yellow }
        'Error'       { Write-Host $LogEntry -ForegroundColor Red }
    }

    Add-Content -Path $LogFile -Value $LogEntry
}

function Test-HeartBeatDNS {

    <#
    .SYNOPSIS
    Validates HeartBeat DNS records and IP connectivity.

    .DESCRIPTION
    Resolves the server, heartbeat and heartbeat-x DNS
    records and performs ICMP connectivity tests against
    each resolved IP address.

    .PARAMETER PingCount
    Number of ICMP echo requests to send.

    .EXAMPLE
    Test-HeartBeatDNS

    Performs DNS and ping validation using four ping attempts.

    .EXAMPLE
    Test-HeartBeatDNS -PingCount 10

    Performs DNS and ping validation using ten ping attempts.

    #>

    [CmdletBinding()]
    param(
        [int]$PingCount = 2
    )

    $FunctionName = $MyInvocation.MyCommand.Name

    Write-Log "Starting $FunctionName"

    try {

        $CS = Get-CimInstance Win32_ComputerSystem

        $Records = @(
            $CS.DNSHostName
            "$($CS.DNSHostName)-HB"
            "$($CS.DNSHostName)-HBX"
        )

        $Failures = 0

        foreach ($Record in $Records) {

            Write-Log "Testing $Record"

            try {

                $IP = Resolve-DnsName `
                    -Name $Record `
                    -Type A `
                    -ErrorAction Stop |
                    Select-Object -ExpandProperty IPAddress -First 1

                Write-Log "Resolved to $IP"

                if (Test-Connection `
                        -ComputerName $IP `
                        -Count $PingCount `
                        -Quiet) {

                    Write-Log "PASS - Ping successful for $IP"
                }
                else {

                    Write-Log -Severity Error "FAIL - Ping failed for $IP"
                    $Failures++
                }
            }
            catch {

                Write-Log -Severity Error "FAIL - DNS resolution failed"
                Write-Log "Exception : $($_.Exception.Message)"

                $Failures++
            }
        }
        
        if ($Failures -eq 0) {

            Write-Log "All DNS and ping tests passed."
            Write-Log "Finished $FunctionName"
            return
        }
        else {

            Write-Log -Severity Error "$Failures validation test(s) failed."
            Write-Log "Finished $FunctionName"
            EXIT 9503
        }

    }
    catch {

        Write-Log "Function failed"
        Write-Log "Exception : $($_.Exception.Message)"
        Write-Log "Line      : $($_.InvocationInfo.ScriptLineNumber)"
        Write-Log "Statement : $($_.InvocationInfo.Line.Trim())"

        Write-Log "Finished $FunctionName"
        EXIT 9599
    }
    Write-Log "Finished $FunctionName"
}

function Disable-OldHeartBeatNIC {

    <#
    .SYNOPSIS
    Disables the legacy HeartBeat-X adapter.

    .DESCRIPTION
    Resolves the HeartBeat-X DNS address, identifies the
    associated adapter and disables the network interface.

    .PARAMETER None
    This function does not accept parameters.

    .EXAMPLE
    DisableOldHeartBeatNIC

    Disables the legacy heartbeat adapter.

    #>

    [CmdletBinding(SupportsShouldProcess)]
    param()

    $FunctionName = $MyInvocation.MyCommand
    Write-Log "Starting $FunctionName"

    try {

        #
        # Resolve legacy heartbeat address
        #
        $cs = Get-CimInstance Win32_ComputerSystem

        $HBXDNS = "$($cs.DNSHostName)-HBX.$($cs.Domain)"
        Write-Log "FQDN:$HBXDNS"

        try {
            $HBXIP = (Resolve-DnsName $HBXDNS -ErrorAction Stop).IPAddress
        }
        catch {
            Write-Log "Failed to resolve DNS name: $HBXDNS"
            Write-Log "Finished $FunctionName"
            EXIT 9601
        }

        Write-Log "Heartbeat-X IP: $HBXIP"

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
            Write-Log -Severity Error "No adapter found with IP address $HBXIP"
            Write-Log "Finished $FunctionName"
            EXIT 9602
        }

        if (($Adapters | Measure-Object).Count -gt 1) {
            Write-Log -Severity Error "Multiple adapters found with IP address $HBXIP"
            $Adapters |
                Select-Object InterfaceAlias, IPAddress |
                Format-Table -AutoSize
                
            Write-Log "Finished $FunctionName"
            EXIT 9603
        }

        $OldHeartBeat = $Adapters.InterfaceAlias

        Write-Log "Legacy heartbeat adapter found: $OldHeartBeat"

        #
        # Safety check
        #
        $Adapter = Get-NetAdapter `
            -Name $OldHeartBeat `
            -ErrorAction Stop

        if ($Adapter.Status -eq 'Disabled') {
            Write-Log -Severity Warning "Adapter $OldHeartBeat is already disabled"
            
            Write-Log "Finished $FunctionName"
            EXIT 9604
        }

        #
        # Disable adapter
        #
        if ($PSCmdlet.ShouldProcess($OldHeartBeat, "Disable legacy heartbeat adapter")) {

            Disable-NetAdapter `
                -Name $OldHeartBeat `
                -Confirm:$false `
                -ErrorAction Stop

            Write-Log "Disabled adapter: $OldHeartBeat"
        }
    }
    catch {
        Write-Log "Function failed"
        Write-Log "Exception : $($_.Exception.Message)"
        Write-Log "Line      : $($_.InvocationInfo.ScriptLineNumber)"
        Write-Log "Statement : $($_.InvocationInfo.Line.Trim())"

        Write-Log -Severity Error "Finished $FunctionName"
        EXIT 9699
    }

    Write-Log "Finished $FunctionName"
}

function Enable-OldHeartBeatNIC {
    <#
    .SYNOPSIS
    Enables the legacy HeartBeat-X adapter.

    .DESCRIPTION
    Locates a disabled X-HeartBeat adapter and enables
    the network interface.

    .PARAMETER None
    This function does not accept parameters.

    .EXAMPLE
    EnableOldHeartBeatNIC

    Enables the legacy heartbeat adapter.

    #>


    [CmdletBinding(SupportsShouldProcess)]
    param()

    $FunctionName = $MyInvocation.MyCommand
    Write-Log "Starting $FunctionName"

    try {

        #
        # Find disabled legacy heartbeat adapter
        #
        $Adapters = Get-NetAdapter -ErrorAction Stop | Where-Object {
            $_.Status -ne "Up" -and $_.Name -eq "X-HeartBeat"
        }

        if (-not $Adapters) {
            Write-Log -Severity Error "Disabled adapter 'X-HeartBeat' not found."
            Write-Log "Finished $FunctionName"
            EXIT 9701
        }

        if (($Adapters | Measure-Object).Count -gt 1) {
            Write-Log -Severity Warning "Multiple adapters named 'X-HeartBeat' found."
            $Adapters |
                Select-Object Name, InterfaceDescription, Status |
                Format-Table -AutoSize

            Write-Log "Finished $FunctionName"
            EXIT 9702
        }

        $DisabledHeartBeat = $Adapters.Name

        Write-Log "Found adapter: $DisabledHeartBeat"

        #
        # Verify adapter is not already enabled
        #
        if ($Adapters.Status -eq "Up") {
            Write-Log -Severity Warning "Adapter '$DisabledHeartBeat' is already enabled."

            Write-Log "Finished $FunctionName"
            EXIT 9703
        }

        #
        # Enable adapter
        #
        if ($PSCmdlet.ShouldProcess($DisabledHeartBeat, "Enable legacy heartbeat adapter")) {

            Enable-NetAdapter `
                -Name $DisabledHeartBeat `
                -Confirm:$false `
                -ErrorAction Stop

            Write-Log "Enabled adapter: $DisabledHeartBeat"
        }

    }
    catch {
        Write-Log "Function failed"
        Write-Log "Exception : $($_.Exception.Message)"
        Write-Log "Line      : $($_.InvocationInfo.ScriptLineNumber)"
        Write-Log "Statement : $($_.InvocationInfo.Line.Trim())"

        Write-Log "Finished $FunctionName"
        EXIT 9799
    }

     Write-Log "Finished $FunctionName"
}
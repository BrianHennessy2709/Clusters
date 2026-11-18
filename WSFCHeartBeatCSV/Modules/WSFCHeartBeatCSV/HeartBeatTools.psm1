<#
.FILENAME
HeartBeatTools.psm1

.DESCRIPTION
Various PowerShell function to help configure new WSFC HeartBeat network including rollback options

.CHANGE HISTORY
    VERSION |DATE   |AUTHOR |DETAILS
    1.0     |N0V 26 |BH
    
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

    Exports baseline information to C:\Windows\Build\Logs.

    .EXAMPLE
    Export-ClusterBaseline -OutputPath D:\Baseline

    Exports baseline information to D:\Baseline.

    #>

    [CmdletBinding()]
    param(
        [string]$OutputPath = "C:\Windows\Build\Logs"
    )


    $FunctionName = $MyInvocation.MyCommand
    Write-Log "Starting $FunctionName"

    if (-not (Test-Path -Path $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath | Out-Null
            Write-Log "$OutputPath did not exist and has been created."
    } 
    else {
        Write-Log "$OutputPath already exists. No action taken."
    }

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
        Write-Log -Severity Error "Adapter already exists with name '$NewNicName'."
        Write-Log "Finished $FunctionName"
        return
    }

    # Construct Heartbeat FQDN & Check DNS Entry
    $HBXDNS = ($cs = Get-CimInstance Win32_ComputerSystem).DNSHostName + '-HBX' + '.' + $cs.Domain

    # Validate DNS Entry
    $HBXIP = (Resolve-DnsName $HBXDNS -ErrorAction SilentlyContinue).IPAddress

    if ($HBXIP -eq $null) {

        Write-Log "HBX DNS Record does not exist for $env:COMPUTERNAME"
        Write-Log "Finished $FunctionName"
        return

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
            return

        }

        if (($IPMatches | Measure-Object).Count -gt 1) {

            Write-Log "Multiple adapters found using HBX IP Address [$HBXIP]. Aborting."

            $IPMatches |
                Select-Object InterfaceAlias, IPAddress |
                Format-Table -AutoSize

            Write-Log "Finished $FunctionName"
            return
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
            return

        }

        # Protection against multiple adapter matches
        if (($Adapter | Measure-Object).Count -gt 1) {

            Write-Log "Multiple adapters matched interface alias '$OldHeartBeat'."
            Write-Log "Finished $FunctionName"
            return

        }

        # Detect already-configured adapter
        if ($Adapter.Name -eq $NewNicName) {

            Write-Log "Adapter already named '$NewNicName'. No action required."
            Write-Log "Finished $FunctionName"
            return 0

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
            return
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
        Write-Log -Severity Error "Adapter '$NewNicName' already exists."
        Write-Log "Finished $FunctionName"
        return
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
        return
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
        return
    }

    if (($Adapters | Measure-Object).Count -gt 1) {

        Write-Log -Severity Error "Multiple possible heartbeat adapters found. Aborting."

        $Adapters |
            Select-Object Name, InterfaceDescription |
            Format-Table -AutoSize
         Write-Log "Finished $FunctionName"
        return
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
       return
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
            return
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
    if ($HBNet.Name -notmatch '^Cluster Network') {
    #if ($HBNet.Name -eq "Heartbeat-$HBPrefix") {

        Write-Log -Severity Error "Matched network is already named:$($HBNet.Name):Aborting to prevent accidental modification."
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
        $LocalNode = $env:COMPUTERNAME

        $RemoteNode = (Get-ClusterNode |
            Where-Object Name -ne $LocalNode).Name

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

        [string]$LogFile = 'C:\Windows\Build\Logs\ClusterHeartBeatScript.log'
    )

    $Date   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $Server = $env:COMPUTERNAME

    $LogEntry = "$Date`t$Server`t$FunctionName`t$Severity`t$Message"

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

        $Domain = $CS.Domain
        $DomainController = $env:LOGONSERVER.TrimStart('\')

        $Records = @(
            $CS.DNSHostName
            "$($CS.DNSHostName)-HB"
            "$($CS.DNSHostName)-HBX"
        )

        $Failures = 0

        foreach ($Record in $Records) {

        # Append the domain unless the hostname is already an FQDN
            $FQDN = if ($Record -match '\.') {
                $Record
            }
            else {
                "$Record.$Domain"
            }
            
            Write-Log "Testing $Record"

            try {

                $IP = Resolve-DnsName `
                    -Name $FQDN `
                    -Type A `
                    -DnsOnly `
                    -Server $DomainController `
                    -ErrorAction Stop |
                    Select-Object -First 1 -ExpandProperty IPAddress

                if (-not $IP) {
                    throw "No IPv4 A record returned for $FQDN"
                }

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
            return
        }

    }
    catch {

        Write-Log "Function failed"
        Write-Log "Exception : $($_.Exception.Message)"
        Write-Log "Line      : $($_.InvocationInfo.ScriptLineNumber)"
        Write-Log "Statement : $($_.InvocationInfo.Line.Trim())"

        Write-Log "Finished $FunctionName"
        return
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

    # Heartbeat DNS record
    #
    $HBName = "$($env:COMPUTERNAME)-HB"

    try {
        $HBIP = (Resolve-DnsName $HBName -Type A -ErrorAction Stop).IPAddress
    }
    catch {
        Write-Log -Severity Error "Failed to resolve DNS name: $HBName"
        Write-Log "Finished $FunctionName"
        return
    }   

        Write-Log "Heartbeat DNS IP: $HBIP"
        $HBNICName = "HeartBeat"

        # Validate HB network before disabling HBX
        $HBAdapter = Get-NetAdapter -Name $HBNICName -ErrorAction SilentlyContinue

        if (-not $HBAdapter) {
            Write-Log -Severity Error "HB adapter '$HBNICName' not found. Aborting HBX disable operation."
            Write-Log "Finished $FunctionName"
            return
        }

        if ($HBAdapter.Status -ne 'Up') {
            Write-Log -Severity Error "HB adapter '$HBNICName' is not Up. Aborting HBX disable operation."
            Write-Log "Finished $FunctionName"
            return
        }

        $HBIPAddress = Get-NetIPAddress -InterfaceAlias $HBNICName -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if (-not $HBIPAddress) {
            Write-Log -Severity Error "HB adapter '$HBNICName' has no IPv4 address configured. Aborting HBX disable operation."
            Write-Log "Finished $FunctionName"
            return
        }

        if (-not (Test-Connection -ComputerName $HBIPAddress.IPAddress -Count 2 -Quiet)) {
            Write-Log -Severity Error "HB adapter '$HBNICName' is configured but not responding. Aborting HBX disable operation."
            Write-Log "Finished $FunctionName"
            return
        }

        Write-Log -Message "HB adapter '$HBNICName' validated successfully. Proceeding with HBX disable."

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
            return
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
            return
        }

        if (($Adapters | Measure-Object).Count -gt 1) {
            Write-Log -Severity Error "Multiple adapters found with IP address $HBXIP"
            $Adapters |
                Select-Object InterfaceAlias, IPAddress |
                Format-Table -AutoSize
                
            Write-Log "Finished $FunctionName"
            return
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
            return
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
        return
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
            return
        }

        if (($Adapters | Measure-Object).Count -gt 1) {
            Write-Log -Severity Warning "Multiple adapters named 'X-HeartBeat' found."
            $Adapters |
                Select-Object Name, InterfaceDescription, Status |
                Format-Table -AutoSize

            Write-Log "Finished $FunctionName"
            return
        }

        $DisabledHeartBeat = $Adapters.Name

        Write-Log "Found adapter: $DisabledHeartBeat"

        #
        # Verify adapter is not already enabled
        #
        if ($Adapters.Status -eq "Up") {
            Write-Log -Severity Warning "Adapter '$DisabledHeartBeat' is already enabled."

            Write-Log "Finished $FunctionName"
            return
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
        return
    }

     Write-Log "Finished $FunctionName"
}

function Set-XHeartbeatClusterNetwork {

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
    $HBXDNS = "$($CS.DNSHostName)-HBX.$($CS.Domain)"

    Write-Log "Resolving heartbeat DNS record: $HBXDNS"

    try {
        $HBXIP = (Resolve-DnsName $HBXDNS -ErrorAction Stop |
            Where-Object {$_.Type -eq 'A'} |
            Select-Object -ExpandProperty IPAddress -First 1)
    }
    catch {
        Write-Log -Severity Error "Failed to resolve $HBXDNS"
        Write-Log "Finished $FunctionName"
        return
    }

    if (-not $HBXIP) {
        Write-Log -Severity Error "No IPv4 address returned from DNS."
        Write-Log "Finished $FunctionName"
        return
    }

    Write-Log "X-Heartbeat IP: $HBXIP"

    # Build subnet prefix
    $HBXPrefix = ($HBXIP -split '\.')[0..2] -join '.'

    Write-Log "Expected subnet prefix: $HBXPrefix"

    # Find matching cluster networks
    $Matches = Get-ClusterNetwork | Where-Object {
        $_.Address -like "$HBXPrefix*"
    }

    if ($Matches.Count -eq 0) {
        Write-Log -Severity Error "No cluster network found matching subnet prefix $HBXPrefix"
        Write-Log "Finished $FunctionName"
        return
    }

    if ($Matches.Count -gt 1) {
        Write-Log -Severity Error "Multiple cluster networks match subnet prefix $HBXPrefix. Aborting."

        $Matches |
            Select-Object Name, Address, Role |
            Format-Table -AutoSize

            Write-Log "Finished $FunctionName"

        return
    }

    $HBXNet = $Matches[0]

    # Additional subnet validation
    $NetworkPrefix = ($HBXNet.Address -split '\.')[0..2] -join '.'

    if ($NetworkPrefix -ne $HBXPrefix) {
        Write-Log -Severity Error @"
Subnet validation failed.

DNS subnet     : $HBXPrefix
Cluster subnet : $NetworkPrefix

No changes made.
"@
        Write-Log "Finished $FunctionName"
        return
    }

    # Prevent renaming an already configured network
    if ($HBXNet.Name -notmatch '^Cluster Network') {
    #if ($HBXNet.Name -eq "Heartbeat-$HBXPrefix") {

        Write-Log -Severity Error "Matched network is already named:$($HBXNet.Name):Aborting to prevent accidental modification."
        Write-Log "Finished $FunctionName"

        return
    }

    
    Write-Log "Validation Summary"
    Write-Log "------------------"
    Write-Log "Cluster       : $($Cluster.Name)"
    Write-Log "DNS Record    : $HBXDNS"
    Write-Log "X-Heartbeat IP  : $HBXIP"
    Write-Log "Network Name  : $($HBXNet.Name)"
    Write-Log "Network Addr  : $($HBXNet.Address)"
    Write-Log "Current Role  : $($HBXNet.Role)"
    Write-Log "New Name      : Heartbeat-$HBXPrefix"
    Write-Log "New Role      : 1"
    

    if ($PSCmdlet.ShouldProcess($HBXNet.Name, "Rename network and set Role=1")) {

        $HBXNet.Name = "Heartbeat-$HBXPrefix"
        $HBXNet.Role = 1

       
        Write-Log "Successfully updated cluster network."
        Write-Log "Name : $($HBXNet.Name)"
    }
    Write-Log "Finished $FunctionName"
}

function Restore-XHeartBeatNICName {

 <#
.SYNOPSIS
Configures the X-HeartBeat network adapter.

.DESCRIPTION
Locates the legacy X-heartBeat adapter, renames it to HeartBeat.

.PARAMETER None
This function does not accept parameters.

.EXAMPLE
Restore-HeartBeatNIC   

#>
    [CmdletBinding()]
    param()
    $FunctionName = $MyInvocation.MyCommand
    Write-Log "Starting $FunctionName"

    try {
        # Expected X-HeartBeat DNS record
        $HBXName = "$($env:COMPUTERNAME)-HBX"
        $HBXIP = (Resolve-DnsName $HBXName -Type A -ErrorAction Stop).IPAddress

        # Find adapter using the HBX DNS IP
        $HBXAdapter = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object {
                $_.IPAddress -eq $HBXIP
            } |
            Select-Object -ExpandProperty InterfaceAlias -First 1

        if (-not $HBXAdapter) {
            Write-Log -Severity Warning "No adapter found using X-HeartBeat DNS IP [$HBXIP]. No changes required."
            Write-Log "Finished $FunctionName"
            return
        }

        # Safety check - only touch the X-HeartBeat adapter
        if ($HBXAdapter -ne 'X-HeartBeat') {
            Write-Log -Severity Error  "Adapter using HBX DNS IP [$HBXIP] is [$HBXAdapter], not [X-HeartBeat]. No changes made."
            Write-Log "Finished $FunctionName"
            return
        }

        Write-Log "Renaming adapter [X-HeartBeat] to [HeartBeat]."

        Rename-NetAdapter `
            -Name 'X-HeartBeat' `
            -NewName 'HeartBeat' `
            -Confirm:$false `
            -ErrorAction Stop

        Write-Log "Successfully renamed [X-HeartBeat] to [HeartBeat]."
        Write-Log "Finished $FunctionName"

        return 
    }
    catch {
        Write-Log -Severity Error "Failed to rename X-HeartBeat adapter. $_" 
        Write-Log "Finished $FunctionName"
        return 
    }
}

function Restore-HeartBeatNIC {

     <#
    .SYNOPSIS
    Configures the HeartBeat network adapter.

    .DESCRIPTION
    Locates the heartBeat adapter, renames it to EthernetHB,
    configures the IP address from DNS and disables DNS
    registration on the adapter.

    .PARAMETER None
    This function does not accept parameters.

    .EXAMPLE
    Restore-HeartBeatNIC   

    #>
    [CmdletBinding()]
    param()

    $FunctionName = $MyInvocation.MyCommand
    Write-Log "Starting $FunctionName"

    try {
        # Expected HeartBeat DNS record
        $HBName = "$($env:COMPUTERNAME)-HB"
        $HBIP = (Resolve-DnsName $HBName -Type A -ErrorAction Stop).IPAddress

        # Find adapter using the HB DNS IP
        $HBAdapter = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object {
                $_.IPAddress -eq $HBIP
            } |
            Select-Object -ExpandProperty InterfaceAlias -First 1

        if (-not $HBAdapter) {
            Write-Log -Severity Warning "No adapter found using HeartBeat DNS IP [$HBIP]. No rollback required."
            Write-Log "Finished $FunctionName"
            return
        }

        # Safety check - only touch the HeartBeat adapter
        if ($HBAdapter -ne 'HeartBeat') {
            Write-Log -Severity Error "Adapter using HB DNS IP [$HBIP] is [$HBAdapter], not [HeartBeat]. No changes made."
            Write-Log "Finished $FunctionName"
            return
        }

        Write-Log "Renaming adapter [HeartBeat] to [EthernetHB]."

        Rename-NetAdapter `
            -Name 'HeartBeat' `
            -NewName 'EthernetHB' `
            -Confirm:$false `
            -ErrorAction Stop

        Write-Log "Resetting [EthernetHB] to DHCP."

        Set-NetIPInterface `
            -InterfaceAlias 'EthernetHB' `
            -Dhcp Enabled `
            -ErrorAction Stop

        Set-DnsClientServerAddress `
            -InterfaceAlias 'EthernetHB' `
            -ResetServerAddresses `
            -ErrorAction Stop

        # Remove any existing static IPv4 addresses
        Get-NetIPAddress `
            -InterfaceAlias 'EthernetHB' `
            -AddressFamily IPv4 `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.PrefixOrigin -eq 'Manual'
            } |
            Remove-NetIPAddress `
                -Confirm:$false `
                -ErrorAction SilentlyContinue

        Write-Log "HeartBeat adapter rollback completed successfully."
        Write-Log "Finished $FunctionName"

        return
    }
    catch {
        Write-Log -Severity Error "EthernetHB to restore HeartBeat NIC. $_"
        Write-Log "Finished $FunctionName"
        return
    }
}

function Remove-HiddenDevices {

    <#
    .SYNOPSIS
    Removes Hidden Devices from Device Manager

    .DESCRIPTION
    # Remove hidden (non-present) Network Adapters
    # Run as Administrator
    # Windows 10 / Windows Server 2016 or later

    .PARAMETER None

    .EXAMPLE
    Remove-HiddenDevices 

    #>

    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Log "Searching for hidden network adapters"

    try {
        # Get all network adapters, including non-present devices
        $AllAdapters = Get-PnpDevice -Class Net -ErrorAction Stop

        # Get currently connected/present network adapters
        $PresentAdapters = Get-PnpDevice -Class Net -PresentOnly -ErrorAction Stop

        # Build list of currently present device instance IDs
        $PresentIDs = @{}
        foreach ($Adapter in $PresentAdapters) {
            $PresentIDs[$Adapter.InstanceId] = $true
        }

        # Identify hidden adapters
        $HiddenAdapters = $AllAdapters | Where-Object {
            -not $PresentIDs.ContainsKey($_.InstanceId)
        }

        if (-not $HiddenAdapters) {
            Write-Log "No hidden network adapters found."
            return
        }

        Write-Log -Severity Warning "`nHidden network adapters found:"

        $HiddenAdapters |
            Format-Table FriendlyName, Status, InstanceId -AutoSize

        Write-Log "`nRemoving hidden network adapters..."

        foreach ($Adapter in $HiddenAdapters) {

            if ($PSCmdlet.ShouldProcess($Adapter.FriendlyName, "Remove device")) {

                Write-Log "Removing: $($Adapter.FriendlyName)"

                & pnputil.exe /remove-device "$($Adapter.InstanceId)"

                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Successfully removed."
                }
                else {
                    Write-Log -Severity Error "Removal failed. Exit code: $LASTEXITCODE"
                }
            }
        }

        Write-Log "`nCompleted. No reboot has been initiated."
    }
    catch {
        Write-Error "An error occurred: $_"
        Write-Log -Severity Error "An error occurred: $_"
    }


    Write-Log "`nRefreshing Plug and Play device enumeration..."

    # Force Windows to rescan devices
    & pnputil.exe /scan-devices

    # Allow PnP to complete
    Start-Sleep -Seconds 5

    # Refresh Device Manager's device enumeration
    $null = Get-PnpDevice -Class Net -ErrorAction SilentlyContinue

    Write-Log "Device enumeration refreshed."

}

function Set-HeartBeatNICCSV {

    <#
    .SYNOPSIS
    Configures the HeartBeat network adapter using a CSV file for network information.

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
        Write-Log -Severity Error "Adapter '$NewNicName' already exists."
        Write-Log "Finished $FunctionName"
        return
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
        return
    }
       

    Write-Log "Heartbeat DNS IP: $HBIP"

    try{

     $CsvPath = "C:\Windows\Build\Config\WSFCHeartBeatCSV\HeartBeatNetworks.csv"
        $NetworkConfig = Import-Csv $CsvPath

        $HBNetworkAddress = ($HBIP -split '\.')[0..2] -join '.'
        $HBNetworkAddress += '.0'

        $HBNetworkConfig = $NetworkConfig |
            Where-Object Network -eq $HBNetworkAddress

            if (-not $HBNetworkConfig) {
            throw "No network configuration found in '$CsvPath' for network '$HBNetworkAddress'."
            }
        }
        catch
        {
         Write-Log -Severity Error "No network configuration found in '$CsvPath' for network '$HBNetworkAddress'."
        Write-Log "Finished $FunctionName"
        return
        }
    #
    # Find candidate adapter
    #
    $Adapters = Get-NetAdapter |
        Where-Object Status -eq Up |
        Where-Object Name -notmatch 'Team|Prod|Management|Data|HeartBeat'

    if (-not $Adapters) {
        Write-Log -Severity Error "Additional Heartbeat adapter not found"
        Write-Log "Finished $FunctionName"
        return
    }

    if (($Adapters | Measure-Object).Count -gt 1) {

        Write-Log -Severity Error "Multiple possible heartbeat adapters found. Aborting."

        $Adapters |
            Select-Object Name, InterfaceDescription |
            Format-Table -AutoSize
         Write-Log "Finished $FunctionName"
        return
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
       return
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
                -PrefixLength $HBNetworkConfig.PrefixLength

            Set-DnsClient `
                -InterfaceAlias $NewNicName `
                -RegisterThisConnectionsAddress $false

            Write-Log "Heartbeat configured as $HBIP"
        }
        catch {
            Write-Log -Severity Error $_.Exception.Message
             Write-Log -ErrorVariable Error  "Finished $FunctionName"
            return
        }
    }

    Write-Log "Finished $FunctionName"
}

function Add-HeartBeatRouteCSV {

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

    $CsvPath = "C:\WINDOWS\Build\Config\WSFCHeartBeatCSV\HeartBeatNetworks.csv"
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
               try {
                $RemoteNode = (Get-ClusterNode |
                Where-Object Name -ne $LocalNode).Name        

            }
            catch{
                Write-Log -Severity Error "Unable to identify remote cluster node."
                Write-Log "Finished $FunctionName"
                return
                }
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

        # Build route information from CSV
        #
        $RouteConfig = $null

        $RemoteIPObj = [System.Net.IPAddress]::Parse($RemoteHBIP)

        #
        # Build route information from CSV
        #
        $RemoteRouteConfig = $null
        $LocalRouteConfig  = $null

        foreach ($Route in $RouteNetworks)
        {
            $MaskBytes = ([System.Net.IPAddress]::Parse($Route.SubnetMask)).GetAddressBytes()

            #
            # Remote HB lookup
            #
            $RemoteIPBytes = ([System.Net.IPAddress]::Parse($RemoteHBIP)).GetAddressBytes()

            $RemoteNetworkBytes = for ($i = 0; $i -lt 4; $i++)
            {
                $RemoteIPBytes[$i] -band $MaskBytes[$i]
            }

            $RemoteNetwork = ([System.Net.IPAddress]::new($RemoteNetworkBytes)).ToString()

            if ($RemoteNetwork -eq $Route.Network)
            {
                $RemoteRouteConfig = $Route
            }

            #
            # Local HB lookup
            #
            $LocalIPBytes = ([System.Net.IPAddress]::Parse($LocalHBIP)).GetAddressBytes()

            $LocalNetworkBytes = for ($i = 0; $i -lt 4; $i++)
            {
                $LocalIPBytes[$i] -band $MaskBytes[$i]
            }

            $LocalNetwork = ([System.Net.IPAddress]::new($LocalNetworkBytes)).ToString()

            if ($LocalNetwork -eq $Route.Network)
            {
                $LocalRouteConfig = $Route
            }
        }

        if (-not $RemoteRouteConfig)
        {
            Write-Log -Severity Error "No matching remote network found for $RemoteHBIP"
            Write-Log "Finished $FunctionName"
            return
        }

        if (-not $LocalRouteConfig)
        {
            Write-Log -Severity Error "No matching local network found for $LocalHBIP"
            Write-Log "Finished $FunctionName"
            return
        }

        $RouteConfig = $RemoteRouteConfig
        $LocalGatewayIP = $LocalRouteConfig.Gateway

        Write-Log "Matched CSV Network : $($RouteConfig.Network)"
        Write-Log "Matched CSV Gateway : $($RouteConfig.Gateway)"
        Write-Log "Matched CSV Mask    : $($RouteConfig.SubnetMask)"

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

function Set-HeartbeatClusterNetworkCSV {

    <#
    .SYNOPSIS
    Configures the Failover Cluster heartbeat network using a CSV file for network information

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

    # Add wait to allow the Cluster Network to create
    Write-Log "Waiting for Cluster Network"
    Start-Sleep -Seconds 10

    # Build expected heartbeat DNS record
    $CS = Get-CimInstance Win32_ComputerSystem
    $HBDNS = "$($CS.DNSHostName)-HB.$($CS.Domain)"

    Write-Log "Resolving heartbeat DNS record: $HBDNS"

    try {
        $HBIP = (Resolve-DnsName $HBDNS -ErrorAction Stop |
            Where-Object { $_.Type -eq 'A' } |
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

    # Get local NIC configuration for the HB IP
    $HBNetIP = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -eq $HBIP } |
        Select-Object -First 1

    if (-not $HBNetIP) {
        Write-Log -Severity Error "Unable to determine subnet information for $HBIP"
        Write-Log "Finished $FunctionName"
        return
    }

    $PrefixLength = $HBNetIP.PrefixLength

    Write-Log "Heartbeat Prefix Length: /$PrefixLength"

    # Calculate network address
    $IPBytes = [System.Net.IPAddress]::Parse($HBIP).GetAddressBytes()

    $Mask = [uint32]::MaxValue
    $Mask = $Mask -shl (32 - $PrefixLength)

    $MaskBytes = @(
        ($Mask -shr 24) -band 255
        ($Mask -shr 16) -band 255
        ($Mask -shr 8) -band 255
        $Mask -band 255
    )

    $NetworkBytes = 0..3 | ForEach-Object {
        $IPBytes[$_] -band $MaskBytes[$_]
    }

    $NetworkAddress = ([System.Net.IPAddress]::new($NetworkBytes)).IPAddressToString

    Write-Log "Expected network address: $NetworkAddress/$PrefixLength"

    # Find matching cluster networks
    $Matches = Get-ClusterNetwork | Where-Object {
        $_.Address -eq $NetworkAddress
    }

    if ($Matches.Count -eq 0) {
        Write-Log -Severity Error "No cluster network found matching network address $NetworkAddress"
        Write-Log "Finished $FunctionName"
        return
    }

    if ($Matches.Count -gt 1) {
        Write-Log -Severity Error "Multiple cluster networks match network address $NetworkAddress. Aborting."

        $Matches |
            Select-Object Name, Address, Role |
            Format-Table -AutoSize

        Write-Log "Finished $FunctionName"
        return
    }

    $HBNet = $Matches[0]

    # Additional validation
    if ($HBNet.Address -ne $NetworkAddress) {
        Write-Log -Severity Error @"
Network validation failed.

Expected network : $NetworkAddress
Cluster network  : $($HBNet.Address)

No changes made.
"@
        Write-Log "Finished $FunctionName"
        return
    }

    # Prevent renaming an already configured network
    if ($HBNet.Name -notmatch '^Cluster Network') {

        Write-Log -Severity Error "Matched network is already named:$($HBNet.Name):Aborting to prevent accidental modification."
        Write-Log "Finished $FunctionName"
        return
    }

    $NewName = "HeartBeat-$NetworkAddress/$PrefixLength"

    Write-Log "Validation Summary"
    Write-Log "------------------"
    Write-Log "Cluster       : $($Cluster.Name)"
    Write-Log "DNS Record    : $HBDNS"
    Write-Log "Heartbeat IP  : $HBIP"
    Write-Log "Prefix Length : $PrefixLength"
    Write-Log "Network Name  : $($HBNet.Name)"
    Write-Log "Network Addr  : $($HBNet.Address)"
    Write-Log "Current Role  : $($HBNet.Role)"
    Write-Log "New Name      : $NewName"
    Write-Log "New Role      : 1"

    if ($PSCmdlet.ShouldProcess($HBNet.Name, "Rename network and set Role=1")) {

        $HBNet.Name = $NewName
        $HBNet.Role = 1

        Write-Log "Successfully updated cluster network."
        Write-Log "Name : $($HBNet.Name)"
    }

    Write-Log "Finished $FunctionName"
}
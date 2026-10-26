function Set-HeartbeatClusterNetwork {

    [CmdletBinding(SupportsShouldProcess)]
    param()

    # Verify Cluster Service exists and is running
    $ClusterService = Get-Service -Name ClusSvc -ErrorAction SilentlyContinue

    if (-not $ClusterService) {
        Write-Error "Cluster Service (ClusSvc) not found on this server."
        return
    }

    if ($ClusterService.Status -ne 'Running') {
        Write-Error "Cluster Service is not running. Current state: $($ClusterService.Status)"
        return
    }

    # Verify cluster connectivity
    try {
        $Cluster = Get-Cluster -ErrorAction Stop
    }
    catch {
        Write-Error "Unable to communicate with the failover cluster."
        return
    }

    Write-Host "Connected to cluster: $($Cluster.Name)"

    # Build expected heartbeat DNS record
    $CS = Get-CimInstance Win32_ComputerSystem
    $HBDNS = "$($CS.DNSHostName)-HB.$($CS.Domain)"

    Write-Host "Resolving heartbeat DNS record: $HBDNS"

    try {
        $HBIP = (Resolve-DnsName $HBDNS -ErrorAction Stop |
            Where-Object {$_.Type -eq 'A'} |
            Select-Object -ExpandProperty IPAddress -First 1)
    }
    catch {
        Write-Error "Failed to resolve $HBDNS"
        return
    }

    if (-not $HBIP) {
        Write-Error "No IPv4 address returned from DNS."
        return
    }

    Write-Host "Heartbeat IP: $HBIP"

    # Build subnet prefix
    $HBPrefix = ($HBIP -split '\.')[0..2] -join '.'

    Write-Host "Expected subnet prefix: $HBPrefix"

    # Find matching cluster networks
    $Matches = Get-ClusterNetwork | Where-Object {
        $_.Address -like "$HBPrefix*"
    }

    if ($Matches.Count -eq 0) {
        Write-Error "No cluster network found matching subnet prefix $HBPrefix"
        return
    }

    if ($Matches.Count -gt 1) {
        Write-Error "Multiple cluster networks match subnet prefix $HBPrefix. Aborting."

        $Matches |
            Select-Object Name, Address, Role |
            Format-Table -AutoSize

        return
    }

    $HBNet = $Matches[0]

    # Additional subnet validation
    $NetworkPrefix = ($HBNet.Address -split '\.')[0..2] -join '.'

    if ($NetworkPrefix -ne $HBPrefix) {
        Write-Error @"
Subnet validation failed.

DNS subnet     : $HBPrefix
Cluster subnet : $NetworkPrefix

No changes made.
"@
        return
    }

    # Prevent renaming an already configured network
    if ($HBNet.Name -notmatch '^Cluster Network') {

        Write-Warning @"
Matched network is already named:

$($HBNet.Name)

This does not appear to be a default Cluster Network.
Aborting to prevent accidental modification.
"@

        return
    }

    Write-Host ""
    Write-Host "Validation Summary" -ForegroundColor Cyan
    Write-Host "------------------"
    Write-Host "Cluster       : $($Cluster.Name)"
    Write-Host "DNS Record    : $HBDNS"
    Write-Host "Heartbeat IP  : $HBIP"
    Write-Host "Network Name  : $($HBNet.Name)"
    Write-Host "Network Addr  : $($HBNet.Address)"
    Write-Host "Current Role  : $($HBNet.Role)"
    Write-Host "New Name      : Heartbeat-$HBPrefix"
    Write-Host "New Role      : 1"
    Write-Host ""

    if ($PSCmdlet.ShouldProcess($HBNet.Name, "Rename network and set Role=1")) {

        $HBNet.Name = "Heartbeat-$HBPrefix"
        $HBNet.Role = 1

        Write-Host ""
        Write-Host "Successfully updated cluster network." -ForegroundColor Green
        Write-Host "Name : $($HBNet.Name)"
    }
}

Set-HeartbeatClusterNetwork 
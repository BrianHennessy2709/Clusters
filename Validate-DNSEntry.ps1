Function Validate-DNSEntry {

[CmdletBinding()]
param
    (
    [Parameter(Mandatory = $true)]
    [System.String]$FQDN
    )

# If name only add DNS

$DomainSuffix = "poc.local"
if(!($FQDN.Contains("."))){$FQDN = "$FQDN.$DomainSuffix"}

$Result = (Resolve-DnsName $FQDN -ErrorAction SilentlyContinue).IPAddress

if ($Result -ne $null)
    {#IP Address Returned
    $RegisteredIPAddress = $Result.Split(" ")[0] #First Address Only
    $DNSState = $true
    }
else
    {#No IP Address Returned
    $Result = "No Address returned from DNS"
    $DNSState = $false
    }

Write-Host "$FQDN IP Address: $Result"
Return $DNSState

}
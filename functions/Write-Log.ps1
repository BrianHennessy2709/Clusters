function Write-Log {
    param(
        [string]$Message
    )

    $Date = $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    $Server = $env:COMPUTERNAME
    $Sev = "Information"

    Write-Host "$Date`t$Server`t$MyName`t$Application`t$Sev`t$Message"
    Add-Content -Path $LogFile `
        -Value "$Date`t$Server`t$MyName`t$Application`t$Sev`t$Message"
}
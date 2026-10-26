function EnableOldHeartBeatNIC {

    [CmdletBinding(SupportsShouldProcess)]
    param()

    $FunctionName = $MyInvocation.MyCommand
    Write-Host "Starting $FunctionName"

    try {

        #
        # Find disabled legacy heartbeat adapter
        #
        $Adapters = Get-NetAdapter -ErrorAction Stop | Where-Object {
            $_.Status -ne "Up" -and $_.Name -eq "X-HeartBeat"
        }

        if (-not $Adapters) {
            Write-Host "Disabled adapter 'X-HeartBeat' not found."
            EXIT 9991
        }

        if (($Adapters | Measure-Object).Count -gt 1) {
            Write-Host "Multiple adapters named 'X-HeartBeat' found."
            $Adapters |
                Select-Object Name, InterfaceDescription, Status |
                Format-Table -AutoSize

            EXIT 9992
        }

        $DisabledHeartBeat = $Adapters.Name

        Write-Host "Found adapter: $DisabledHeartBeat"

        #
        # Verify adapter is not already enabled
        #
        if ($Adapters.Status -eq "Up") {
            Write-Host "Adapter '$DisabledHeartBeat' is already enabled."
            EXIT 9993
        }

        #
        # Enable adapter
        #
        if ($PSCmdlet.ShouldProcess($DisabledHeartBeat, "Enable legacy heartbeat adapter")) {

            Enable-NetAdapter `
                -Name $DisabledHeartBeat `
                -Confirm:$false `
                -ErrorAction Stop

            Write-Host "Enabled adapter: $DisabledHeartBeat"
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

EnableOldHeartBeatNIC
<#

.FILENAME
    Cluster_Heartbeat.ps1
.DESCRIPTION
    Cleans up modules & scripts foor Windws Defender Featue remediation
.CHANGE HISTORY
    VERION | DATE   | AUTHOR | DETIALS
    0.1    | NOV 26 | BH     | TEST

#>

###########################################################################################
# Set Script details and Import Modules

$BuildModulePath = "C:\Windows\Build\Modules"

foreach ($Module in (Get-ChildItem -Path $BuildModulePath -Include '*.psm1' -Recurse)){

        Import-Module $Module -Force

        }
###########################################################################################

Enable-OldHeartBeatNIC
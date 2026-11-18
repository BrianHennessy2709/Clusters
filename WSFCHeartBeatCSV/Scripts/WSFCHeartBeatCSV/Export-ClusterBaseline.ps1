<#

.FILENAME
    Export-ClusterBaseline.ps1
.DESCRIPTION
    Exports WSFC Configuration to various log files for point in time configration
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

Export-ClusterBaseline
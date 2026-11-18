<#

.FILENAME
    Cleanuo_WSFCHeartBeatCSV.ps1
.DESCRIPTION
    Cleans up modules & scripts foor Windws Defender Featue remediation
.CHANGE HISTORY
    VERION | DATE   | AUTHOR | DETIALS
    0.1    | NOV 26 | BH     | TEST

#>

#Clear Script Folder
Remove-Item -Path C:\Windows\Build\Scripts\WSFCHeartBeatCSV -Recurse -Force

#Clear Modules Folder
Remove-Item -Path C:\Windows\Build\Modules\WSFCHeartBeatCSV -Recurse -Force

#Clear Config Folder
Remove-Item -Path C:\Windows\Build\Config\WSFCHeartBeatCSV -Recurse -Force

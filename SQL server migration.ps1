#requires -version 3
<#
.SYNOPSIS
Simple SQL Server Migration with the dbatools modules.

.DESCRIPTION
"SQL Server Migration" consolidates the most important migration tools from the dbatools (from Chrissy LeMaire) into one simple and nice menu. 
This is useful when you're looking to migrate entire instances from Server A to Server B, but it is less flexible than using the underlying FUNCTIONs. 

.NOTES
Version:        3.0
Author:         Johannes Groiss
Date:           31.08.2018
Purpose/Change: Initial script development

.LINK
https://www.croix.at/blog/simple-structured-sql-server-migration-with-powershell-and-the-dbatools/
#>
    

#---------------------------------------------------------[Initialisations]--------------------------------------------------------
# install https://dbatools.io/download/
IF (!(Get-Module -ListAvailable -Name dbatools)){
    Install-Module dbatools 
    Import-Module dbatools
    Get-Command -Module dbatools
}

#-----------------------------------------------------------[FUNCTIONs]------------------------------------------------------------
FUNCTION Get-ScriptDirectory{
    $Invocation = (Get-Variable MyInvocation -Scope 1).Value
    Split-Path $Invocation.MyCommand.Path
}

FUNCTION Mig-CertainDatabases{
    IF (Test-Path "$ScriptPath\Databases.txt"){
        Get-Content "$ScriptPath\Databases.txt" | % {
            IF ($(Get-DbaDatabase -Database "$_" -SqlInstance $SettingSourceServer)){
                Copy-DbaDatabase -Database "$_" -Source $SettingSourceServer -Destination $SettingDestinationServer -BackupRestore -NetworkShare $SettingMigShare -Force -NumberFiles 1 #-WhatIf
            }
        }
    } ELSE {
        return "Create a $ScriptPath\Databases.txt with all your certain databases you want to migrate.`nAfter that, come back and choose the same option again.`n"
        break
    }
}

FUNCTION Show-Menu{
    cls
    Write-Host "┌──────────────────────────────────────────┐" -ForegroundColor Cyan
    Write-Host "│   Welcome to SQL Server Migration V3.0   │" -ForegroundColor Cyan
    Write-Host "└──────────────────────────────────────────┘" -ForegroundColor Cyan

    Write-Host " FROM: $($SettingSourceServer.ToUpper()) `n └>TO: $($SettingDestinationServer.ToUpper())`n       └>SHARE: $SettingMigShare`n"
    IF ($Force){Write-Host " Attention: FORCE is active" -ForegroundColor Red}

    Write-Host " Press '1' to check db-server compatibility [default]"
    IF (!(Test-Path "$ScriptPath\Databases.txt")){
        Write-Host " Press '2' to copy all databases and overwrite on target system"
    }ELSE{
        Write-Host " Press '3' to copy only databases from the databases.txt"
    }
    Write-Host " Press '4' to copy all user objects in system databases (this can take a second)"
    Write-Host " Press '5' to copy all logins"
    Write-Host " Press '6' to copy all jobs"
    Write-Host " Press '7' to syncs only login permissions, roles, etc"
    Write-Host " Press '8' to copy SQL Central Management Server"
    Write-Host " Press '9' to clean up orphaned users on Server $SettingDestinationServer"
    IF (!$Force){Write-Host " Write 'FORCE' to enable the FORCE Parameter (with overwrite)"}
    IF ($Force){Write-Host " Write 'ENDFORCE' to disable the FORCE Parameter"}
    Write-Host " Press 'q' to quit.`n"
}


#----------------------------------------------------------[Declarations]----------------------------------------------------------
$ScriptPath = Get-ScriptDirectory
if($(Test-Path "$ScriptPath\settings.ini")){
    write-host "[*] load $ScriptPath\settings.ini"
    Get-Content "$ScriptPath\settings.ini" -ErrorAction Stop | foreach-object -begin {$setting=@{}} -process {$x=[regex]::split($_,'='); if(($x[0].CompareTo("") -ne 0) -and ($x[0].StartsWith("[") -ne $True)) { $setting.Add($x[0], $x[1]) } } 
    $SettingSharePath = $($setting.SmbShare)
    $SettingSourceServer = $($setting.SourceServer)
    $SettingDestinationServer = $($setting.DestinationServer)
} ELSE {
    Write-Host "I miss the settings.ini, but don't worry. :(" -ForegroundColor Red
    $SettingSharePath = read-host "[*] set migration directory"
    $SettingSourceServer = read-host "[*] set source Server"
    $SettingDestinationServer = read-host "[*] set destination server"
}

IF ($SettingSharePath){
    $ShareName = $SettingSharePath.Split('\')
    $ShareName = $ShareName[$($ShareName.count)-1]

    IF (!(Test-path "$SettingSharePath")){
        write-host "[*] create folder $SettingMigShare" -ForegroundColor Yellow
        New-Item "$SettingSharePath" –type directory
    }
   
    IF ([bool]$(gwmi -class win32_share | where {$_.Path -eq "$SettingSharePath"}) -eq $false){
        write-host "[*] create share $ShareName" -ForegroundColor Yellow
        New-SmbShare –Name "$ShareName" –Path "$SettingSharePath" -FullAccess "Administrators" -ChangeAccess "Everyone"
        write-host "[*] done" -ForegroundColor Yellow
    }
    $SettingMigShare = $(gwmi -class win32_share | where {$_.Path -eq "$SettingSharePath"}).Name
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------
# CHECK CONNECTION TO SERVER
write-host "[*] test connection"
IF (($(Test-DbaConnection $SettingSourceServer -Verbose).ConnectSuccess -eq "True") -and ($(Test-DbaConnection $SettingDestinationServer -Verbose).ConnectSuccess -eq "True")){
    $ShowMenu = $true
} ELSE {
    $ShowMenu = $false
}

Test-DbaCmConnection

IF ($ShowMenu){
    do{
        Show-Menu
        $input = Read-Host "Select option"
        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()

        $OutputLog = "$($SettingSourceServer.Split(".")[0])-to-$($SettingDestinationServer.Split(".")[0])-migration.log"

        Start-Transcript -path $ScriptPath\$OutputLog -append

        switch ($input){
            {($_ -eq "") -or ($_ -eq "1")}{Test-DbaMigrationConstraint -Source $SettingSourceServer -Destination $SettingDestinationServer | ft Database,Notes,SourceVersion,DestinationVersion; break}
            '2' {Copy-DbaDatabase -Source $SettingSourceServer -Destination $SettingDestinationServer -ALL -BackupRestore -NetworkShare $SettingMigShare -NumberFiles 1 -Force; break}
            '3' {Mig-CertainDatabases; break}  
            '4' {Copy-SqlSysDbUserObjects -Source $SettingSourceServer -Destination $SettingDestinationServer; break} 
            '5' {Copy-DbaLogin -Source $SettingSourceServer -Destination $SettingDestinationServer -Force:$Force; break}
            '6' {Copy-DbaAgentJob -Source $SettingSourceServer -Destination $SettingDestinationServer -Force:$Force; break}
            '7' {Copy-DbaLogin -Source $SettingSourceServer -Destination $SettingDestinationServer -SyncOnly -Force:$Force; break}
            '8' {Copy-SqlPolicyManagement -Source $SettingSourceServer -Destination $SettingDestinationServer -Force:$Force; Copy-SqlCentralManagementServer -Source $SettingSourceServer -Destination $SettingDestinationServer -Force:$Force; break}
            '9' {Remove-DbaOrphanUser -SqlServer $SettingDestinationServer -Confirm -Force:$Force; break}
            'FORCE' {$Force=$true}
            'ENDFORCE' {$Force=$false}
            'q' {return}
        }
        Stop-Transcript
        $ErrorActionPreference="SilentlyContinue"
        write-host elapsed time: ($elapsed.Elapsed.toString().Split(".")[0])
        write-host detaild migration log $ScriptPath\$OutputLog.
        pause
    }
    until ($input -eq 'q')
} ELSE {
    cls
    Write-Host "something went wrong, check your settings, permission, and connection to source-target server" -ForegroundColor Red
    
    Test-Connection $SettingSourceServer
    Test-Connection $SettingDestinationServer

    Test-SqlConnection $SettingSourceServer
    Test-SqlConnection $SettingDestinationServer
}

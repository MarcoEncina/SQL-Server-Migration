#requires -version 3
<#
.SYNOPSIS
Simple SQL Server Migration with the dbatools modules.

.DESCRIPTION
"SQL Server Migration" consolidates the most important migration tools from the dbatools (from Chrissy LeMaire) into one simple and nice menu. 
This is useful when you're looking to migrate entire instances from Server A to Server B, but it is less flexible than using the underlying functions. 

.NOTES
Version:        2.1
Author:         Johannes Groiss
Date:           11.05.2017
Purpose/Change: Initial script development

.LINK
https://www.croix.at/blog/simple-structured-sql-server-migration-with-powershell-and-the-dbatools/
#>


#---------------------------------------------------------[Initialisations]--------------------------------------------------------
# install ps module by Chrissy LeMaire
# https://gallery.technet.microsoft.com/scriptcenter/Use-PowerShell-to-Migrate-86c841df
if (!(Get-Module -ListAvailable -Name dbatools)){
    Remove-Module dbatools -ErrorAction SilentlyContinue
    $url = 'https://github.com/ctrlbold/dbatools/archive/master.zip'
    $path = Join-Path -Path (Split-Path -Path $profile) -ChildPath '\Modules\dbatools'
    $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
    $zipfile = "$temp\sqltools.zip"

    if (!(Test-Path -Path $path)){
	    Write-Output "Creating directory: $path"
	    New-Item -Path $path -ItemType Directory | Out-Null 
    } else { 
	    Write-Output "Deleting previously installed module"
	    Remove-Item -Path "$path\*" -Force -Recurse 
    }

    Write-Output "Downloading archive from github"
    try{
	    Invoke-WebRequest $url -OutFile $zipfile
    }
    catch{
       #try with default proxy and usersettings
       Write-Output "Probably using a proxy for internet access, trying default proxy settings"
       (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
       Invoke-WebRequest $url -OutFile $zipfile
    }

    # Unblock if there's a block
    Unblock-File $zipfile -ErrorAction SilentlyContinue

    Write-Output "Unzipping"
    # Keep it backwards compatible
    $shell = New-Object -COM Shell.Application
    $zipPackage = $shell.NameSpace($zipfile)
    $destinationFolder = $shell.NameSpace($temp)
    $destinationFolder.CopyHere($zipPackage.Items())

    Write-Output "Cleaning up"
    Move-Item -Path "$temp\dbatools-master\*" $path
    Remove-Item -Path "$temp\dbatools-master"
    Remove-Item -Path $zipfile

    Import-Module "$path\dbatools.psd1" -Force

    Write-Output "Done! Please report any bugs to clemaire@gmail.com."
    Get-Command -Module dbatools
    Write-Output "`n`nIf you experience any function missing errors after update, please restart PowerShell or reload your profile."
}

#-----------------------------------------------------------[Functions]------------------------------------------------------------
function Get-ScriptDirectory{
    $Invocation = (Get-Variable MyInvocation -Scope 1).Value
    Split-Path $Invocation.MyCommand.Path
}

function Set-MigShare ($dir){
    $LocalServerName = $(Get-WmiObject Win32_Computersystem).name
    if (!(Test-path "$dir")){
        write-host "Create Folder $dir" -ForegroundColor Yellow
        New-Item "$dir" –type directory | Out-Null
     
        write-host "Create Share SQL-Migration-Sync" -ForegroundColor Yellow
        New-SmbShare –Name “SQL-Migration-Sync” –Path "$dir" -FullAccess "Administrators" -ChangeAccess "Everyone" | Out-Null
    }
    return "\\$LocalServerName\SQL-Migration-Sync"
}

function Mig-CertainDatabases{
    if (Test-Path "$ScriptPath\Databases.txt"){
        $MigDatabases = Get-Content "$ScriptPath\Databases.txt" -ErrorAction Stop
        $MigDatabases | % {
            Copy-SqlDatabase -Source $SettingSourceServer -Destination $SettingDestinationServer -BackupRestore -NetworkShare $SettingMigShare -databases "$_" -Force #-WhatIf
        }
    } else{
        return "Create a $ScriptPath\Databases.txt with all your certain databases you want to migrate.`nAfter that, come back and choose the same option again.`n"
    }
}

function Show-Menu{
    cls
    Write-Host "┌──────────────────────────────────────────┐" -ForegroundColor Cyan
    Write-Host "│   Welcome to SQL Server Migration V2.1   │" -ForegroundColor Cyan
    Write-Host "└──────────────────────────────────────────┘" -ForegroundColor Cyan

    Write-Host " FROM: $($SettingSourceServer.ToUpper()) `n └>TO: $($SettingDestinationServer.ToUpper())`n"
    if ($Force){Write-Host " Attention: FORCE is active" -ForegroundColor Red}

    Write-Host " Press '1' to check db-server compatibility [default]"
    Write-Host " Press '2' to copy all databases and overwrite on target system"
    Write-Host " Press '3' to copy only certain databases"
    Write-Host " Press '4' to copy all user objects in system databases (this can take a second)"
    Write-Host " Press '5' to copy all logins"
    Write-Host " Press '6' to copy all jobs"
    Write-Host " Press '7' to syncs only login permissions, roles, etc"
    Write-Host " Press '8' to copy SQL Central Management Server"
    Write-Host " Press '9' to clean up orphaned users on Server $SettingDestinationServer"
    if (!$Force){Write-Host " Write 'FORCE' to enable the FORCE Parameter (with overwrite)"}
    if ($Force){Write-Host " Write 'ENDFORCE' to disable the FORCE Parameter"}
    Write-Host " Press 'q' to quit.`n"
}


#----------------------------------------------------------[Declarations]----------------------------------------------------------
$ScriptPath = Get-ScriptDirectory
if($(Test-Path "$ScriptPath\settings.ini")){
    Get-Content "$ScriptPath\settings.ini" -ErrorAction Stop | foreach-object -begin {$setting=@{}} -process {$x=[regex]::split($_,'='); if(($x[0].CompareTo("") -ne 0) -and ($x[0].StartsWith("[") -ne $True)) { $setting.Add($x[0], $x[1]) } } 
    $SettingMigShare = Set-MigShare $($setting.SmbShare)
    $SettingSourceServer = $($setting.SourceServer)
    $SettingDestinationServer = $($setting.DestinationServer)
} else{
    Write-Host "I miss the settings.ini, but don't worry. :(" -ForegroundColor Red
    $SettingMigShare = read-host "[*]set migration directory"
    $SettingMigShare = Set-MigShare $SettingMigShare
    $SettingSourceServer = read-host "[*]set source Server"
    $SettingDestinationServer = read-host "[*]set destination server"
}


#-----------------------------------------------------------[Execution]------------------------------------------------------------
# CHECK CONNECTION TO SERVER
if (($(Test-SqlConnection $SettingSourceServer).ConnectSuccess -eq "True") -and ($(Test-SqlConnection $SettingDestinationServer).ConnectSuccess -eq "True")){
    $ShowMenu = $true
} else {
    $ShowMenu = $false
}

if ($ShowMenu){
    do{
        Show-Menu
        $input = Read-Host "Select option"
        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()

        $OutputLog = "$($SettingSourceServer.Split(".")[0])-to-$($SettingDestinationServer.Split(".")[0])-migration.log"

        Start-Transcript -path $ScriptPath\$OutputLog -append

        switch ($input){
            {($_ -eq "") -or ($_ -eq "1")}{Test-SqlMigrationConstraint -Source $SettingSourceServer -Destination $SettingDestinationServer | ft Database,Notes,SourceVersion,DestinationVersion; break}
            '2' {Copy-SqlDatabase -Source $SettingSourceServer -Destination $SettingDestinationServer -ALL -BackupRestore -NetworkShare $SettingMigShare -Force; break}
            '3' {Mig-CertainDatabases; break}  
            '4' {Copy-SqlSysDbUserObjects -Source $SettingSourceServer -Destination $SettingDestinationServer; break} 
            '5' {Copy-SqlLogin -Source $SettingSourceServer -Destination $SettingDestinationServer -Force:$Force; break}
            '6' {Copy-SqlJobServer -Source $SettingSourceServer -Destination $SettingDestinationServer -Force:$Force; break}
            '7' {Copy-SqlLogin -Source $SettingSourceServer -Destination $SettingDestinationServer -SyncOnly -Force:$Force; break}
            '8' {Copy-SqlPolicyManagement -Source $SettingSourceServer -Destination $SettingDestinationServer -Force:$Force; Copy-SqlCentralManagementServer -Source $SettingSourceServer -Destination $SettingDestinationServer -Force:$Force; break}
            '9' {Remove-SqlOrphanUser -SqlServer $SettingDestinationServer -Confirm -Force:$Force; break}
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
} else {
    cls
    Write-Host "something went wrong, check your settings, permission, and connection to source-target server" -ForegroundColor Red
    
    Test-Connection $SettingSourceServer
    Test-Connection $SettingDestinationServer

    Test-SqlConnection $SettingSourceServer
    Test-SqlConnection $SettingDestinationServer
}
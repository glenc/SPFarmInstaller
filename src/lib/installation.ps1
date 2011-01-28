# ---------------------------------------------------------------
# Installation Functions
# ---------------------------------------------------------------

function CheckInstallationAccount($config) {
    $farmAccount = $config.ManagedAccounts.Account | Where-Object {$_.name -eq $config.Farm.FarmSvcAccount}
    if ($env:USERDOMAIN + "\" + $env:USERNAME -eq $farmAccount) {
        warn "Running install using Farm Account"
    }
}

function CheckSQLAccess($config) {
    $dbServer = $config.Farm.DatabaseServer
    
    $sqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $sqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $sqlConnection.ConnectionString = "Server=$dbServer;Database=master;Integrated Security=True"
    $sqlCmd.CommandText = "SELECT HAS_DBACCESS('master')"
    $sqlCmd.Connection = $sqlConnection
    $sqlCmd.CommandTimeout = 10
    try {
        $sqlCmd.Connection.Open()
        $sqlCmd.ExecuteReader() | Out-Null
    } catch {
        Write-Error $_
        warn " - Connection failed to SQL server or instance '$dbServer'!"
        warn " - Check the server (or instance) name, or verify rights for $env:USERDOMAIN\$env:USERNAME"
        $SqlCmd.Connection.Close()
        Pause
        exit
    }
    info " - $env:USERDOMAIN\$env:USERNAME has access."
    $SqlCmd.Connection.Close()
}

function IsSharePointInstalled {
    return Test-Path "$env:CommonProgramFiles\Microsoft Shared\Web Server Extensions\14\BIN\stsadm.exe"
}

function InstallPrerequisites($config) {
    $pathToBits = $config.Installation.PathToBits
    $pathToPrereqs = "$pathToBits\PrerequisiteInstallerFiles"
    $offline = ($config.Installation.OfflineInstallation -eq "True")
    
    if (IsSharePointInstalled) {
        info "Prerequisites appear to be already installed - skipping."
        return
    }
    
    try {
        if ($offline) {
            info " - Installing prerequisites from $pathToPrereqs"
            $argList = "/unattended `
/SQLNCli:`"$pathToPrereqs\sqlncli.msi`" /ChartControl:`"$pathToPrereqs\MSChart.exe`" `
/NETFX35SP1:`"$pathToPrereqs\dotnetfx35.exe`" /PowerShell:`"$pathToPrereqs\Windows6.0-KB968930-x64.msu`" `
/KB976394:`"$pathToPrereqs\Windows6.0-KB976394-x64.msu`" `
/KB976462:`"$pathToPrereqs\Windows6.1-KB976462-v2-x64.msu`" `
/IDFX:`"$pathToPrereqs\Windows6.0-KB974405-x64.msu`" `
/IDFXR2:`"$pathToPrereqs\Windows6.1-KB974405-x64.msu`" `
/Sync:`"$pathToPrereqs\Synchronization.msi`" `
/FilterPack:`"$pathToPrereqs\FilterPack\FilterPack.msi`" `
/ADOMD:`"$pathToPrereqs\SQLSERVER2008_ASADOMD10.msi`" `
/ReportingServices:`"$pathToPrereqs\rsSharePoint.msi`" `
/Speech:`"$pathToPrereqs\SpeechPlatformRuntime.msi`" `
/SpeechLPK:`"$pathToPrereqs\MSSpeech_SR_en-US_TELE.msi`""
            
            Start-Process "$pathToBits\PrerequisiteInstaller.exe" -Wait -ArgumentList $argList                                                                 
            if (-not $?) {throw}
        } else {
            info " - Installing prerequisites from remote store..."
            Start-Process "$pathToBits\PrerequisiteInstaller.exe" -Wait -ArgumentList "/unattended" -WindowStyle Minimized
            if (-not $?) {throw}
        }
    } catch {
        error "Error: $LastExitCode"
        if     ($LastExitCode -eq "1") {throw " - Another instance of this application is already running"}
        elseif ($LastExitCode -eq "2") {throw " - Invalid command line parameter(s)"}
        elseif ($LastExitCode -eq "1001") {throw " - A pending restart blocks installation"}
        elseif ($LastExitCode -eq "3010") {throw " - A restart is needed"}
        else   {throw " - An unknown error occurred installing prerequisites"}
    }

    # Parsing most recent PreRequisiteInstaller log for errors or restart requirements, since $LastExitCode doesn't seem to work...
    $preReqLog = get-childitem $env:TEMP | ? {$_.Name -like "PrerequisiteInstaller.*"} | Sort-Object -Descending -Property "LastWriteTime" | Select-Object -first 1
    if ($preReqLog -eq $null) {
        warn " - Could not find PrerequisiteInstaller log file"
    } else {
        # Get error(s) from log
        $preReqLastError = $preReqLog | select-string -SimpleMatch -Pattern "Error" -Encoding Unicode | ? {$_.Line  -notlike "*Startup task*"}
        if ($preReqLastError) {
            warn $preReqLastError.Line
            $preReqLastReturncode = $preReqLog | select-string -SimpleMatch -Pattern "Last return code" -Encoding Unicode | Select-Object -Last 1
            if ($preReqLastReturnCode) {warn $preReqLastReturncode.Line}
            info " - Review the log file and try to correct any error conditions."
            Pause
            Invoke-Item $env:TEMP\$PreReqLog
            exit
        }
        
        # Look for restart requirement in log
        $preReqRestartNeeded = $preReqLog | select-string -SimpleMatch -Pattern "0XBC2=3010" -Encoding Unicode
        if ($preReqRestartNeeded) {
            warn " - One or more of the prerequisites requires a restart."
            info " - Run the script again after restarting to continue."
            Pause
            exit
        }
    }
        
    info "All Prerequisite Software installed successfully."
}

function InstallSharePoint($config) {
    $pathToBits = $config.Installation.PathToBits
    $pathToConfigFile = $config.Installation.PathToInstallConfig
    
    if (IsSharePointInstalled) {
        info "SharePoint binaries appear to be already installed - skipping."
        return
    }
    
    if (-not (Test-Path "$pathToBits\setup.exe")) {
        warn "Could not find SharePoint setup.exe"
        Pause
        exit
    }
    
    try {
        Start-Process "$pathToBits\setup.exe" -ArgumentList "/config `"$pathToConfigFile`"" -WindowStyle Minimized -Wait
        If (-not $?) {throw}
    } catch {
        warn "Error $LastExitCode occurred running $bits\setup.exe"
        Pause
        exit
    }
    
    # Parsing most recent SharePoint Server Setup log for errors or restart requirements, since $LastExitCode doesn't seem to work...
    $setupLog = get-childitem $env:TEMP | ? {$_.Name -like "SharePoint Server Setup*"} | Sort-Object -Descending -Property "LastWriteTime" | Select-Object -first 1
    if ($setupLog -eq $null) {
        warn " - Could not find SharePoint Server Setup log file!"
        Pause
        exit
    } else {
        # Get error(s) from log
        $setupLastError = $setupLog | select-string -SimpleMatch -Pattern "Error:" | Select-Object -Last 1 #| ? {$_.Line  -notlike "*Startup task*"}
        if ($setupLastError) {
            warn $setupLastError.Line
            info " - Review the log file and try to correct any error conditions."
            Pause
            Invoke-Item $env:TEMP\$SetupLog
            exit
        }
        
        # Look for restart requirement in log
        $setupRestartNotNeeded = $setupLog | select-string -SimpleMatch -Pattern "System reboot is not pending."
        if (!($setupRestartNotNeeded)) {
            info " - SharePoint setup requires a restart."
            info " - Run the script again after restarting to continue."
            Pause
            exit
        }
    }
    
    info "Waiting for SharePoint Products and Technologies Wizard to launch..."
    while ((Get-Process |?{$_.ProcessName -like "psconfigui*"}) -eq $null) {
        write-progress
        sleep 1
    }
    info " - Exiting Products and Technologies Wizard - using Powershell instead!"
    Stop-Process -Name psconfigui
}
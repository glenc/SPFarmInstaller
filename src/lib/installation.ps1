# ---------------------------------------------------------------
# Installation Functions
# ---------------------------------------------------------------

function CheckInstallationAccount($farmDefinition) {
    $farmAccount = $farmDefinition.Get_Item("FarmSvcAccount")
    if ($env:USERDOMAIN + "\" + $env:USERNAME -eq $farmAccount) {
        warn "Running install using Farm Account"
    }
}

function CheckSQLAccess($farmDefinition) {
    $dbServer = $farmDefinition.Get_Item("DatabaseServer")
    
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
		break
	}	
	info " - $env:USERDOMAIN\$env:USERNAME has access."
	$SqlCmd.Connection.Close()
}

function IsSharePointInstalled {
    return Test-Path "$env:CommonProgramFiles\Microsoft Shared\Web Server Extensions\14\BIN\stsadm.exe"
}

function InstallPrerequisites([string]$pathToBits, [bool]$offline) {
    if (IsSharePointInstalled) {
        info "Prerequisites appear to be already installed - skipping."
        return
    }
    
    try {
        if ($offline) {
            Start-Process "$pathToBits\PrerequisiteInstaller.exe" -Wait -ArgumentList "/unattended `
																				/SQLNCli:`"$pathToBits\PrerequisiteInstallerFiles\sqlncli.msi`" `
																				/ChartControl:`"$pathToBits\PrerequisiteInstallerFiles\MSChart.exe`" `
																				/NETFX35SP1:`"$pathToBits\PrerequisiteInstallerFiles\dotnetfx35.exe`" `
																				/PowerShell:`"$pathToBits\PrerequisiteInstallerFiles\Windows6.0-KB968930-x64.msu`" `
																				/KB976394:`"$pathToBits\PrerequisiteInstallerFiles\Windows6.0-KB976394-x64.msu`" `
																				/KB976462:`"$pathToBits\PrerequisiteInstallerFiles\Windows6.1-KB976462-v2-x64.msu`" `
																				/IDFX:`"$pathToBits\PrerequisiteInstallerFiles\Windows6.0-KB974405-x64.msu`" `
																				/IDFXR2:`"$pathToBits\PrerequisiteInstallerFiles\Windows6.1-KB974405-x64.msu`" `
																				/Sync:`"$pathToBits\PrerequisiteInstallerFiles\Synchronization.msi`" `
																				/FilterPack:`"$pathToBits\PrerequisiteInstallerFiles\FilterPack\FilterPack.msi`" `
																				/ADOMD:`"$pathToBits\PrerequisiteInstallerFiles\SQLSERVER2008_ASADOMD10.msi`" `
																				/ReportingServices:`"$pathToBits\PrerequisiteInstallerFiles\rsSharePoint.msi`" `
																				/Speech:`"$pathToBits\PrerequisiteInstallerFiles\SpeechPlatformRuntime.msi`" `
																				/SpeechLPK:`"$pathToBits\PrerequisiteInstallerFiles\MSSpeech_SR_en-US_TELE.msi`""																		
			If (-not $?) {throw}
        } else {
            Start-Process "$pathToBits\PrerequisiteInstaller.exe" -Wait -ArgumentList "/unattended" -WindowStyle Minimized
			If (-not $?) {throw}
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
			If ($preReqLastReturnCode) {Write-Warning $preReqLastReturncode.Line}
			info " - Review the log file and try to correct any error conditions."
			Pause
			Invoke-Item $env:TEMP\$PreReqLog
			break
		}
        
		# Look for restart requirement in log
		$preReqRestartNeeded = $preReqLog | select-string -SimpleMatch -Pattern "0XBC2=3010" -Encoding Unicode
		if ($preReqRestartNeeded) {
			warn " - One or more of the prerequisites requires a restart."
			info " - Run the script again after restarting to continue."
			Pause
			break
		}
	}
        
    info "All Prerequisite Software installed successfully."
}

function InstallSharePoint([string]$pathToBits, [string]$pathToConfigFile) {
    if (IsSharePointInstalled) {
        info "SharePoint binaries appear to be already installed - skipping."
        return
    }
    
    if (-not (Test-Path "$pathToBits\setup.exe")) {
        warn "Could not find SharePoint setup.exe"
        Pause
        break
    }
    
    try {
        Start-Process "$pathToBits\setup.exe" -ArgumentList "/config `"$pathToConfigFile`"" -WindowStyle Minimized -Wait
        If (-not $?) {throw}
    } catch {
        warn "Error $LastExitCode occurred running $bits\setup.exe"
        break
    }
    
	# Parsing most recent SharePoint Server Setup log for errors or restart requirements, since $LastExitCode doesn't seem to work...
	$setupLog = get-childitem $env:TEMP | ? {$_.Name -like "SharePoint Server Setup*"} | Sort-Object -Descending -Property "LastWriteTime" | Select-Object -first 1
    if ($setupLog -eq $null) {
        warn " - Could not find SharePoint Server Setup log file!"
        Pause
        break
    } else {
		# Get error(s) from log
		$setupLastError = $setupLog | select-string -SimpleMatch -Pattern "Error:" | Select-Object -Last 1 #| ? {$_.Line  -notlike "*Startup task*"}
		if ($setupLastError) {
			warn $setupLastError.Line
			info " - Review the log file and try to correct any error conditions."
			Pause
			Invoke-Item $env:TEMP\$SetupLog
			break
		}
        
		# Look for restart requirement in log
		$setupRestartNotNeeded = $setupLog | select-string -SimpleMatch -Pattern "System reboot is not pending."
		if (!($setupRestartNotNeeded)) {
			info " - SharePoint setup requires a restart."
			info " - Run the script again after restarting to continue."
			Pause
			break
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
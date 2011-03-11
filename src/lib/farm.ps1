# ---------------------------------------------------------------
# Farm Functions
# ---------------------------------------------------------------

function IsJoinedToFarm($config) {
    debug " - Checking if server is joined to farm"
    $configDb = $config.Farm.ConfigDB
    try {
        $farm = Get-SPFarm | Where-Object {$_.Name -eq $configDb} -ErrorAction SilentlyContinue
    } catch {""}
    return $farm -eq $null
}

function CreateOrJoinFarm($config) {
    $configDb = $config.Farm.ConfigDB
    $dbServer = $config.Farm.DatabaseServer
    $passPhrase = GetSecureString $config.Farm.Passphrase
    
    $isNewFarm = $false
    
    $connectionResult = Connect-SPConfigurationDatabase -DatabaseName "$configDb" -Passphrase $passPhrase -DatabaseServer "$dbServer" -ErrorAction SilentlyContinue
    if (-not $?) {
        info "Farm does not exist.  Creating new Farm"
        sleep 5
        CreateNewFarm $config
        
        $isNewFarm = $true
        
    } else {
        info "Joined farm."
    }
    
    info " - Installing Help Collection..."
    Install-SPHelpCollection -All
    
    info " - Securing Resources..."
    Initialize-SPResourceSecurity
    
    info " - Installing Services..."
    Install-SPService
    
    info " - Installing Features..."
    Install-SPFeature -AllExistingFeatures -Force
    
    info " - Installing Application Content..."
    Install-SPApplicationContent
    
    # version registry workaround for bug in PS-based install
    $build = "$($(Get-SPFarm).BuildVersion.Major).0.0.$($(Get-SPFarm).BuildVersion.Build)"
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Shared Tools\Web Server Extensions\14.0\' -Name Version -Value $build -ErrorAction SilentlyContinue | Out-Null
    
    # start timer service
    StartTimerService
    
    return $isNewFarm
}

function CreateNewFarm($config) {
    debug " - Creating new farm"
    $configDb = $config.Farm.ConfigDB
    $dbServer = $config.Farm.DatabaseServer
    $passPhrase = GetSecureString $config.Farm.Passphrase
    $centralAdminContentDb = $config.Farm.CentralAdminContentDB
    $farmCred = GetCredential $config.Farm.FarmSvcAccount $config
    
    New-SPConfigurationDatabase -DatabaseName "$configDb" -DatabaseServer "$dbServer" -Passphrase $passPhrase -AdministrationContentDatabaseName "$centralAdminContentDb" -FarmCredentials $farmCred
    if (-not $?) { throw }
    else { info "Created new farm." }
}

function CreateCentralAdmin($config) {
    info "Creating SharePoint Central Administratino Site"
    $port = $config.Farm.CentralAdminPort
    
    try {
        $newCentralAdmin = New-SPCentralAdministration -Port $port -WindowsAuthProvider "NTLM" -ErrorVariable err
        if (-not $?) {throw}
        
        debug " - Waiting for Central Admin site to provision..."
        $centralAdmin = Get-SPWebApplication -IncludeCentralAdministration | ? {$_.Url -like "http://$($env:COMPUTERNAME):$port*"}
        
        while ($centralAdmin.Status -ne "Online") {
            write-progress
            sleep 1
            $centralAdmin = Get-SPWebApplication -IncludeCentralAdministration | ? {$_.Url -like "http://$($env:COMPUTERNAME):$port*"}
        }
        debug " - Done!"
        
    } catch {
        if ($err -like "*update conflict*") {
            warn "A concurrency error occured, trying again."
            CreateCentralAdmin $config
        } else {
            Write-Output $_
            Pause
            break
        }
    }
}

function StartTimerService() {
    $svc = Get-Service "SPTimerV4"
    if ($svc.Status -ne "Running") {
        info "Starting timer service"
        Start-Service "SPTimerV4"
        while ($svc.Status -ne "Running") {
            show-progress
            sleep 1
            $svc = Get-Service "SPTimerV4"
        }
    }
}

function AddFarmAccountToLocalAdminGroup($config) {
    $farmAcct = GetManagedAccountUsername $config.Farm.FarmSvcAccount $config
    
    $farmAcctDomain,$farmAcctUser = $farmAcct -Split "\\"
    
    try {
        ([ADSI]"WinNT://$env:COMPUTERNAME/Administrators,group").Add("WinNT://$farmAcctDomain/$farmAcctUser")
        If (-not $?) {throw}
    } catch {
        info "  $farmAcct is already an Administrator."
    }
}

function ConfigureOutgoingEmail($config) {
    try {
        debug "  Configuring Outgoing Email..."
        
        $SMTPServer = $config.Farm.OutgoingEmail.smtpServer
        $emailAddress = $config.Farm.OutgoingEmail.emailAddress
        $replyToAddress = $config.Farm.OutgoingEmail.replyToAddress
        
        $loadasm = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint")
        $SPGlobalAdmin =  New-Object Microsoft.SharePoint.Administration.SPGlobalAdmin
        $SPGlobalAdmin.UpdateMailSettings($SMTPServer, $emailAddress, $replyToAddress, 65001)
    } catch {
        Write-Output $_
    }
}
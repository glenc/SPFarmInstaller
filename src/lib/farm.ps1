# ---------------------------------------------------------------
# Farm Functions
# ---------------------------------------------------------------

function IsJoinedToFarm($config) {
    debug "Checking if server is joined to farm"
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
    
    # version registry workaround for bug in PS-based install
    $build = "$($(Get-SPFarm).BuildVersion.Major).0.0.$($(Get-SPFarm).BuildVersion.Build)"
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Shared Tools\Web Server Extensions\14.0\' -Name Version -Value $build -ErrorAction SilentlyContinue | Out-Null
    
    return $isNewFarm
}

function CreateNewFarm($config) {
    debug "Creating new farm"
    $configDb = $config.Farm.ConfigDB
    $dbServer = $config.Farm.DatabaseServer
    $passPhrase = GetSecureString $config.Farm.Passphrase
    $centralAdminContentDb = $config.Farm.CentralAdminContentDB
    $farmCred = GetCredential $config.Farm.FarmSvcAccount $config
    
    New-SPConfigurationDatabase -DatabaseName "$configDb" -DatabaseServer "$dbServer" -Passphrase $passPhrase -AdministrationContentDatabaseName "$centralAdminContentDb" -FarmCredentials $farmCred
    if (-not $?) { throw }
    else { info "Created new farm." }
}

function InitializeNewFarm($config) {
    info "Initializing the new SharePoint Farm"
    
    try {
        info " - Installing Help Collection..."
        Install-SPHelpCollection -All
            
        info " - Securing Resources..."
        Initialize-SPResourceSecurity
        
        info " - Installing Services..."
        Install-SPService
        
        info " - Installing Features..."
        Install-SPFeature -AllExistingFeatures -Force
        
        info " - Creating Central Admin..."
        CreateCentralAdmin $config
        
        info " - Installing Application Content..."
        Install-SPApplicationContent
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
    
    info "Completed initial farm/server config."
}

function CreateCentralAdmin($config) {
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
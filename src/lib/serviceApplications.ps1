# ---------------------------------------------------------------
# Service Application Functions
# ---------------------------------------------------------------


function ProvisionMetadataServiceApplications($config) {
    foreach ($def in $config.ServiceApplications.ManagedMetadataApplication) {
        $serviceName = $def.name
        $dbName = $def.DBName
        $partitioned = $def.Partitioned -eq "True"
        $adminAccount = GetManagedAccountUsername $def.AdminAccount $config
        
        info "Creating Managed Metadata Service Application"
        debug "  Name:" $serviceName
        debug "  AppPool:" $def.AppPool.name
        debug "  DBName:" $dbName
        if ($partitioned) { debug "  Partitioned" }
        
        $createCmd = "New-SPMetadataServiceApplication -DatabaseName `"$dbName`" -AdministratorAccount `"$adminAccount`" -FullAccessAccount `"$adminAccount`""
        if ($partitioned) { $createCmd += " -PartitionMode" }
        
        $proxyCmd = "New-SPMetadataServiceApplicationProxy"
        if ($partitioned) { $proxyCmd += " -PartitionMode" }
        
        ProvisionServiceApplication $def $createCmd $proxyCmd $config
    }
}

function ProvisionUserProfileServiceApplications($config) {
    foreach ($def in $config.ServiceApplications.UserProfileApplication) {
        $serviceName = $def.name
        $profileDb = $def.ProfileDB
        $syncDb = $def.ProfileSyncDB
        $socialDb = $def.SocialDB
        $mySiteHostUrl = $def.MySites.HostUrl
        $personalSitePath = $def.MySites.PersonalSitePath
        $partitioned = $def.Partitioned -eq "True"
        
        info "Creating User Profile Service Application"
        debug "  Name:" $serviceName
        debug "  AppPool:" $def.AppPool.name
        if ($partitioned) { debug "  Partitioned" }
        
        $createCmd = "New-SPProfileServiceApplication -ProfileDBName `"$profileDb`" -ProfileSyncDBName `"$syncDb`" -SocialDBName `"$socialDb`" -MySiteHostLocation `"$mySiteHostUrl`" -MySiteManagedPath `"$personalSitePath`""
        if ($partitioned) { $createCmd += " -PartitionMode" }
        
        $proxyCmd = "New-SPProfileServiceApplicationProxy"
        if ($partitioned) { $proxyCmd += " -PartitionMode" }
        
        CreateMySiteHost
        
        ProvisionServiceApplication $def $createCmd $proxyCmd $config
        
        # start sync service
    }
}

function CreateMySiteHost {
    warn "not implemented"
    
}

function ProvisionServiceApplication($appDefinition, [string]$serviceAppCmd, [string]$proxyCmd, $config) {
    $appName = $appDefinition.name
    $appPoolName = $appDefinition.AppPool.name
    try {
        if ((Get-SPServiceApplication | ? {$_.DisplayName -eq $appName}) -eq $null) {
            
            # Get or create app pool
            $appPoolAccount = GetOrCreateManagedAccount $appDefinition.AppPool.account $config
            if ($appPoolAccount -eq $null) { throw "Managed account not found" }
            
            $appPool = GetOrCreateServiceApplicationPool $appPoolName $appPoolAccount
            
            # create actual service app
            debug "  Creating service application..."
            $serviceAppCmd += " -Name `"$appName`" -ApplicationPool `$appPool"
            $createAppCmd = $ExecutionContext.InvokeCommand.NewScriptBlock($serviceAppCmd)
            $serviceApp = Invoke-Command -ScriptBlock $createAppCmd
            if (-not $?) { throw "- Failed to create service application" }
            
            # create proxy
            debug "  Creating application proxy..."
            $proxyCmd += " -Name `"$appName Proxy`" -ServiceApplication `$serviceApp"
            $createProxyCmd = $ExecutionContext.InvokeCommand.NewScriptBlock($proxyCmd)
            Invoke-Command -ScriptBlock $createProxyCmd | Out-Null
            if (-not $?) { throw "- Failed to create service application proxy" }
            
            # assign permissions
            ApplyPermissionsToServiceApplication $serviceApp $appDefinition.Permissions $config
            
            debug "  done"
            
        } else {
            warn "Service application already exists"
        }
    } catch {
        Write-Output $_
    }
}

function GetOrCreateServiceApplicationPool([string]$name, $identity) {
    debug "  Getting Application Pool $name, creating if necessary..."
    $appPool = Get-SPServiceApplicationPool $name -ea SilentlyContinue
    
    if ($appPool -eq $null) { 
        $appPool = New-SPServiceApplicationPool $name -account $identity
        if (-not $?) { throw "Failed to create an application pool" }
    }
    
    return $appPool
}

function ApplyPermissionsToServiceApplication($serviceAppToSecure, $permissions, $config) {
    ## Get ID of "Service"
    $serviceAppIDToSecure = $serviceAppToSecure.Id
    
    ## Get security for app
    $serviceAppSecurity = Get-SPServiceApplicationSecurity $serviceAppIDToSecure
            
    ## Get the Claims Principals for each identity specified
    foreach ($perm in $permissions.Grant) {
        $identity = GetManagedAccountUsername $perm.account $config
        $principal = New-SPClaimsPrincipal -Identity $identity -IdentityType WindowsSamAccountName
        Grant-SPObjectSecurity $serviceAppSecurity -Principal $principal -Rights $perm.rights
    }
    
    ## Apply the changes to the Service application
    Set-SPServiceApplicationSecurity $serviceAppIDToSecure -objectSecurity $serviceAppSecurity
}
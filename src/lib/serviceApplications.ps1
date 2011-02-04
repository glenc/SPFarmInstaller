# ---------------------------------------------------------------
# Service Application Functions
# ---------------------------------------------------------------

function GetOrCreateServiceApplicationPool([string]$name, $identity) {
    info "Getting Application Pool $name, creating if necessary..."
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

function ProvisionMetadataServiceApp($config) {
    foreach ($def in $config.ServiceApplications.ManagedMetadataApplication) {
        debug $def
        info "Creating Managed Metadata Service Application"
        debug "  Name:" $def.name
        debug "  AppPool:" $def.AppPool.name
        debug "  DBName:" $def.DBName
        
        $partitioned = $def.Partitioned -eq "True"
        if ($partitioned) { debug "  Partitioned" }
        
        try {
            ## Create a Metadata Service Application
            if((Get-SPServiceApplication | ? {$_.DisplayName -eq $serviceName}) -eq $null) {
                ## Get Managed Account
                $appPoolAccount = GetOrCreateManagedAccount $def.AppPool.account $config
                if ($appPoolAccount -eq $null) { throw "Managed Account not found" }
                
                # Get App Pool
                $appPool = GetOrCreateServiceApplicationPool $def.AppPool.name $appPoolAccount
            
                info "Creating Managed Metadata Service"
                
                $adminAccount = GetManagedAccountUsername $def.AdminAccount $config
                debug "  Admin Account: $adminAccount"
                
                ## Create Service App
                info "Creating Metadata Service Application..."
                if ($partitioned) {
                    $metaDataServiceApp  = New-SPMetadataServiceApplication -PartitionMode -Name $def.name -ApplicationPool $appPool -DatabaseName $def.DBName -AdministratorAccount $adminAccount -FullAccessAccount $adminAccount
                    if (-not $?) { throw "Failed to create Metadata Service Application" }
                } else {
                    $metaDataServiceApp  = New-SPMetadataServiceApplication -Name $def.name -ApplicationPool $appPool -DatabaseName $def.DBName -AdministratorAccount $adminAccount -FullAccessAccount $adminAccount
                    if (-not $?) { throw "Failed to create Metadata Service Application" }
                }
                

                ## create proxy
                info "Creating Metadata Service Application Proxy..."
                $metaDataServiceAppProxy  = New-SPMetadataServiceApplicationProxy -Name "$serviceName Proxy" -ServiceApplication $metaDataServiceApp -DefaultProxyGroup
                if (-not $?) { throw "- Failed to create Metadata Service Application Proxy" }
                
                
                ## Grant Rights to App
                info "Granting rights to Metadata Service Application..."
                ApplyPermissionsToServiceApplication $metaDataServiceApp $def.Permissions $config
                
                
                ## All Done
                info "Done creating Managed Metadata Service."
            } else { 
                info "Managed Metadata Service already exists."
            }
        } catch {
            Write-Output $_ 
        }
    }
}

function ProvisionUserProfileServiceApp($definitions) {
    foreach ($def in $definitions) {
        $serviceName = $def.Get_Item("Name")
        
        info "Creating User Profile Service Application '$serviceName'"
        try {
            if ((Get-SPServiceApplication -Name $serviceName) -eq $null) {
                
                # configure My Site Host and Site Collection
                CreateMySiteHost
                
                # create app
                $profileServiceApp = CreateUserProfileServiceApp $def
                
                # Create Proxy
                CreateUserProfileServiceProxy $serviceName $profileServiceApp
                
                ## Grant Rights to App
                ApplyPermissionsToServiceApplication $serviceName $def.Get_Item("Permissions")
                
                ## All Done
                info "Done"
                
            } else {
                warn "User profile service application was already created."
            }
        } catch {
        	warn "Could not create application"
        }
    }
}

function CreateMySiteHost {
    warn "not implemented"
    
}

function CreateUserProfileServiceApp($definition) {
    $appPoolAccountName = $def.Get_Item("AppPoolAccount")
    $appPoolAccountPwd = $_.Get_Item("AppPoolAccountPwd")
    $appPoolName = $_.Get_Item("AppPoolName")
    $profileDB = $_.Get_Item("ProfileDB")
    $syncDB = $_.Get_Item("ProfileSyncDB")
    $socialDB = $_.Get_Item("SocialDB")
    $partitioned = $_.Get_Item("Partitioned")
    $mySiteUrl = $_.Get_Item("MySiteUrl")
    $mySitePort = $_.Get_Item("MySitePort")

    ## Get Managed Account
    $appPoolAccount = GetOrCreateManagedAccount $appPoolAccountName $appPoolAccountPwd
      if ($appPoolAccount -eq $null) { throw "Managed Account $appPoolAccountName not found" }
    
    # Get App Pool
    $appPool = GetOrCreateServiceApplicationPool $appPoolName $appPoolAccount
    
    # Create Service App
    if ($partitioned) {
        New-SPProfileServiceApplication -PartitionMode -Name "$serviceName" -ApplicationPool "$appPoolName" -ProfileDBName $profileDB -ProfileSyncDBName $syncDB -SocialDBName $socialDB -MySiteHostLocation "$mySiteURL:$mySitePort"
        if (-not $?) {throw "Failed to create user profile service"}
    } else {
        New-SPProfileServiceApplication -Name "$serviceName" -ApplicationPool "$appPoolName" -ProfileDBName $profileDB -ProfileSyncDBName $syncDB -SocialDBName $socialDB -MySiteHostLocation "$mySiteURL:$mySitePort"
        if (-not $?) {throw "Failed to create user profile service"}
    }
    
    debug "Wait for service to come online"
    $profileServiceApp = Get-SPServiceApplication -Name $serviceName
    while ($profileServiceApp.Status -ne "Online") {
        write-progress
        sleep 1
        $profileServiceApp = Get-SPServiceApplication -Name $serviceName
    }
    
    return $profileServiceApp
}

function CreateUserProfileServiceProxy($serviceName, $profileServiceApp) {
    $profileServiceAppProxy  = New-SPProfileServiceApplicationProxy -Name "$serviceName Proxy" -ServiceApplication $profileServiceApp -DefaultProxyGroup
    if (-not $?) { throw " - Failed to create $serviceName Proxy" }
}
# ---------------------------------------------------------------
# Service Application Functions
# ---------------------------------------------------------------


# ---------------------------------------------------------------
# Managed Metadata
# ---------------------------------------------------------------

function ProvisionMetadataServiceApplications($config) {
    if ($config.ServiceApplications.ManagedMetadataApplication -eq $null) {
        return
    }
    
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
        
        $proxyCmd = "New-SPMetadataServiceApplicationProxy -DefaultProxyGroup"
        if ($partitioned) { $proxyCmd += " -PartitionMode" }
        
        ProvisionServiceApplication $def $createCmd $proxyCmd $config
    }
}

# ---------------------------------------------------------------
# Enterprise Search
# ---------------------------------------------------------------

function ProvisionEnterpriseSearchServiceApplications($config) {
    $apps = $config.ServiceApplications.EnterpriseSearchApplication
    $service = $config.ServiceApplications.EnterpriseSearchService
    
    if ($service -eq $null -and $apps -ne $null) {
        throw { "Cannot provision enterprise search applications without an enterprise search service defined" }
    }
    
    # first provision the service itself
    ProvisionEnterpriseSearchService $config
    
    # next provision each application
    if ($apps -eq $null) {
        return
    }
    
    foreach ($def in $apps) {
        $serviceName = $def.name
        $partitioned = $def.Partitioned -eq "True"
        
        info "Creating Enterprise Search Application"
        debug "  Name:" $serviceName
        debug "  AppPool:" $def.AppPool.name
        if ($partitioned) { debug "  Partitioned" }
        
        $existingApp = Get-SPEnterpriseSearchServiceApplication -Identity $serviceName -ErrorAction SilentlyContinue
        if ($existingApp -ne $null) {
            debug "  Already exists"
            break
        }
        
        debug "  Creating new search application..."
        $searchApp = CreateEnterpriseSearchApplication $def $config
        
        debug "  Starting search services on servers..."
        StartEnterpriseSearchServices $searchApp $config
        
        debug "  Configuring crawl topology..."
        ConfigureCrawlTopology $searchApp $def $config
        
        debug "  Configure query topology..."
        ConfigureQueryTopology $searchApp $def $config
        
        debug "  Setting default content access account..."
        SetDefaultContentAccessAccount $searchApp $def $config
        
        debug "  Activating topology..."
        ActivateTopology $searchApp $config
        
        debug "  Create proxy..."
        CreateSearchProxy $searchApp $def $config
        
        debug "  Set Search Start Points..."
        SetCrawlStartPoints $searchApp $config
    }
    
    debug "  Creating search shares..."
    CreateSearchShares $config
}

function ProvisionEnterpriseSearchService($config) {
    debug "  Provisioning search service..."
    
    $def = $config.ServiceApplications.EnterpriseSearchService
    $account = $config.ManagedAccounts.Account | ? {$_.name -eq $def.SearchServiceAccount}
    $pwd = GetSecureString $account.password
    
    Get-SPEnterpriseSearchService | Set-SPEnterpriseSearchService `
                                        -ContactEmail $def.ContactEmail `
                                        -ConnectionTimeout $def.ConnectionTimeout `
                                        -AcknowledgementTimeout $def.AcknowledgementTimeout `
                                        -ProxyType $def.ProxyType `
                                        -IgnoreSSLWarnings $def.IgnoreSSLWarnings `
                                        -InternetIdentity $def.InternetIdentity `
                                        -PerformanceLevel $def.PerformanceLevel `
                                        -ServiceAccount $account.username `
                                        -ServicePassword $pwd
    
    debug "  Setting default index location..."
    Get-SPEnterpriseSearchServiceInstance | foreach {
        $_ | Set-SPEnterpriseSearchServiceInstance -DefaultIndexLocation $def.IndexLocation -ErrorAction SilentlyContinue
    }
}

function CreateEnterpriseSearchApplication($definition, $config) {
    # Get or create app pool
    $tmpAccount = GetOrCreateManagedAccount $definition.AppPool.account $config
    if ($tmpAccount -eq $null) { throw "Managed account not found" }
    $appPool = GetOrCreateServiceApplicationPool $definition.AppPool.name $tmpAccount
    
    $tmpAccount = GetOrCreateManagedAccount $definition.AdminAppPool.account $config
    if ($tmpAccount -eq $null) { throw "Managed account not found" }
    $adminAppPool = GetOrCreateServiceApplicationPool $definition.AdminAppPool.name $tmpAccount
    
    # create new application
    $partitioned = $definition.Partitioned -eq "True"
    $searchApp = New-SPEnterpriseSearchServiceApplication -Name $definition.name -DatabaseName $definition.DBName -ApplicationPool $appPool -AdminApplicationPool $adminAppPool -Partitioned:$partitioned -SearchApplicationType $definition.SearchServiceApplicationType
    
    return $searchApp
}

function StartEnterpriseSearchServices($searchApp, $config) {
    $allSearchServers = GetAllSearchServers $config
    $searchAdminServers = GetAllServerNamesForService "EnterpriseSearchAdminComponent" $config
    foreach ($server in $allSearchServers) {
        $svc = Get-SPEnterpriseSearchServiceInstance | ? {$_.Server.Name -eq $server}
        if ($svc -eq $null) { throw "Unable to get search service on server $server" }
        
        if ($svc.Status -ne "Online") {
            debug "  $server"
            $svc | Start-SPEnterpriseSearchServiceInstance
            while ($svc.Status -ne "Online") {
                show-progress
                sleep 1
                $svc = Get-SPEnterpriseSearchServiceInstance | ? {$_.Server.Name -eq $server}
            }
        }
        
        if ($searchAdminServers -contains $server) {
            Set-SPEnterpriseSearchAdministrationComponent -SearchApplication $searchApp -SearchServiceInstance $svc
            $component = $searchApp | Get-SPEnterpriseSearchAdministrationComponent
            if ($component.Initialized -eq $false) {
                while($component.Initialized -eq $false) {
                    show-progress
                    sleep 1
                    $component = $searchApp | Get-SPEnterpriseSearchAdministrationComponent
                }
            }
        }
    }
}

function SetDefaultContentAccessAccount($searchApp, $definition, $config) {
    $account = $config.ManagedAccounts.Account | ? {$_.name -eq $definition.ContentAccessAccount}
    $pwd = GetSecureString $account.password
    $searchApp | Set-SPEnterpriseSearchServiceApplication -DefaultContentAccessAccountName $account.username -DefaultContentAccessAccountPassword $pwd
}

function ConfigureCrawlTopology($searchApp, $definition, $config) {
    $crawlTopology = Get-SPEnterpriseSearchCrawlTopology -SearchApplication $searchApp | where {$_.State -eq "Inactive"}
    if ($crawlTopology -eq $null) {
        debug "  Creating new topology..."
        $crawlTopology = $searchApp | New-SPEnterpriseSearchCrawlTopology
    }
    
    # store values for later
    $indexLocation = $config.ServiceApplications.EnterpriseSearchService.IndexLocation
    $storeDbName = $definition.DBName + "_CrawlStore"
    
    # get crawl servers
    $crawlServers = GetAllServerNamesForService "EnterpriseSearchCrawl" $config
    foreach ($server in $crawlServers) {
        $svc = Get-SPEnterpriseSearchServiceInstance | ? {$_.Server.Name -eq $server}
        $crawlComponent = $crawlTopology.CrawlComponents | where { $_.ServerName -eq $server }
        if ($crawlComponent -eq $null) {
            debug "  - adding crawl component for server $server"
            $crawlStore = $searchApp.CrawlStores | where { $_.Name -eq $storeDbName }
            $crawlComponent = New-SPEnterpriseSearchCrawlComponent `
                                -SearchServiceInstance $svc `
                                -SearchApplication $searchApp `
                                -CrawlTopology $crawlTopology `
                                -CrawlDatabase $crawlStore.Id.ToString() `
                                -IndexLocation $indexLocation
        }
    }
}

function ConfigureQueryTopology($searchApp, $definition, $config) {
    $queryTopology = Get-SPEnterpriseSearchQueryTopology -SearchApplication $searchApp | where {$_.State -eq "Inactive"}
    if ($queryTopology -eq $null) {
        debug "  Creating new topology..."
        $queryTopology = $searchApp | New-SPEnterpriseSearchQueryTopology -Partitions $definition.Partitions
    }
    
    # store values for later
    $shareName = $config.ServiceApplications.EnterpriseSearchService.ShareName
    $propDbName = $definition.DBName + "_PropertyStore"
    
    # get query servers
    $queryServers = GetAllServerNamesForService "EnterpriseSearchQuery" $config
    foreach ($server in $queryServers) {
        $svc = Get-SPEnterpriseSearchServiceInstance | ? {$_.Server.Name -eq $server}
        $queryComponent = $queryTopology.QueryComponents | where { $_.ServerName -eq $server }
        if ($queryComponent -eq $null) {
            debug "  - adding query component for server $server"
            $partition = ($queryTopology | Get-SPEnterpriseSearchIndexPartition)
            $queryComponent = New-SPEnterpriseSearchQueryComponent -IndexPartition $partition -QueryTopology $queryTopology -SearchServiceInstance $svc -ShareName $shareName
            $propertyStore = $searchApp.PropertyStores | where { $_.Name -eq $propDbName }
            $partition | Set-SPEnterpriseSearchIndexPartition -PropertyDatabase $propertyStore.Id.ToString()
        }
    }
}

function CreateSearchProxy($searchApp, $definition, $config) {
    $name = $definition.name + " Proxy"
    $partitioned = $definition.Partitioned -eq "True"
    $proxy = New-SPEnterpriseSearchServiceApplicationProxy -Name $name -SearchApplication $searchApp -Partitioned:$partitioned
    if ($proxy.Status -ne "Online") {
        $proxy.Status = "Online"
        $proxy.Update()
    }
}

function ActivateTopology($searchApp, $config) {
    debug "  Activating crawl topology..."
    $crawlTopology = Get-SPEnterpriseSearchCrawlTopology -SearchApplication $searchApp | where {$_.State -eq "Inactive"}
    $crawlTopology | Set-SPEnterpriseSearchCrawlTopology -Active -Confirm:$false
    while ($true) {
        $ct = Get-SPEnterpriseSearchCrawlTopology -Identity $crawlTopology -SearchApplication $searchApp
        $state = $ct.CrawlComponents | where {$_.State -ne "Ready"}
        if ($ct.State -eq "Active" -and $state -eq $null) {
            break
        }
        show-progress
        sleep 1
    }
    
    # remove original
    $searchApp | Get-SPEnterpriseSearchCrawlTopology | where {$_.State -eq "Inactive"} | Remove-SPEnterpriseSearchCrawlTopology -Confirm:$false
    
    debug "  Activating query topology..."
    $queryTopology = Get-SPEnterpriseSearchQueryTopology -SearchApplication $searchApp | where {$_.State -eq "Inactive"}
    $queryTopology | Set-SPEnterpriseSearchQueryTopology -Active -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
    while ($true) {
        $qt = Get-SPEnterpriseSearchQueryTopology -Identity $queryTopology -SearchApplication $searchApp
        $state = $qt.QueryComponents | where {$_.State -ne "Ready"}
        if ($qt.State -eq "Active" -and $state -eq $null) {
            break
        }
        show-progress
        sleep 1
    }
    
    # remove original
    $searchApp | Get-SPEnterpriseSearchQueryTopology | where {$_.State -eq "Inactive"} | Remove-SPEnterpriseSearchQueryTopology -Confirm:$false
}

function SetCrawlStartPoints($searchApp, $config) {
    $startPoints = @()
    
    # build a list of all web apps
    foreach ($url in $config.WebApplications.WebApplication.Url) {
        $startPoints += $url
    }
    
    # create sp3:// start points from all my site hosts
    foreach ($mySiteHostUrl in $config.ServiceApplications.UserProfileApplication.MySites.HostUrl) {
        # extract host portion only
        $uri = [uri]$mySiteHostUrl
        $startPoints += "sps3://" + $uri.Host + ":" + $uri.Port
    }
    
    $startAddresses = [string]::join(",", $startPoints)
    debug "  Start Addresses: $startAddresses"
    $searchApp | Get-SPEnterpriseSearchCrawlContentSource | Set-SPEnterpriseSearchCrawlContentSource -StartAddresses $startAddresses
}

function CreateSearchShares($config) {
    $svcDescription = $config.ServiceApplications.EnterpriseSearchService

    $localPath = $svcDescription.IndexLocation
    $shareName = $svcDescription.ShareName
    
    $searchServers = @()
    $searchServers += GetAllServerNamesForService "EnterpriseSearchCrawl" $config
    $searchServers += GetAllServerNamesForService "EnterpriseSearchQuery" $config
    $searchServers = $searchServers | Select-Object -Unique
    
    foreach ($serverName in $searchServers) {
        # create share
        $wmiObj = Get-WmiObject -List -ComputerName $serverName | where-object -FilterScript {$_.Name -eq "Win32_Share"}
        $wmiObj.InvokeMethod("Create", ($localPath, $shareName, 0))
        
        # set permissions on share
        $sd = (new-object management.managementclass Win32_SecurityDescriptor).CreateInstance() 
        $ace = (new-object management.managementclass Win32_ace).CreateInstance() 
        $Trustee = (new-object management.managementclass win32_trustee).CreateInstance()
        
        $wss_wpg = Get-WmiObject Win32_Group -ComputerName $serverName | where-object { $_.Name -eq "WSS_WPG" }
        
        $Trustee.Domain = $serverName
        $Trustee.Name = "WSS_WPG"
        $Trustee.SIDString = $wss_wpg.SID
        
        $ace.AccessMask = 1245631
        $ace.AceType = 0
        $ace.AceFlags = 3
        $ace.trustee = $Trustee
        $sd.DACL = @($ace.psobject.baseObject)
        
        $share = Get-WmiObject win32_share -ComputerName $serverName -filter "name='$shareName'"
        
        $inparams = $share.GetMethodParameters("setShareInfo")
        $inparams["Access"] = $sd.psobject.baseObject
        
        $share.invokeMethod("setShareInfo", $inparams, $null)
    }
}

function GetAllSearchServers($config) {
    $servers = @()
    $servers += GetAllServerNamesForService "EnterpriseSearchCrawl" $config
    $servers += GetAllServerNamesForService "EnterpriseSearchQuery" $config
    $servers += GetAllServerNamesForService "EnterpriseSearchAdminComponent" $config
    
    return $servers | Select-Object -Unique
}

# ---------------------------------------------------------------
# User Profiles
# ---------------------------------------------------------------

function ProvisionUserProfileServiceApplications($config) {
    if ($config.ServiceApplications.UserProfileApplication -eq $null) {
        return
    }
    
    foreach ($def in $config.ServiceApplications.UserProfileApplication) {
        $serviceName = $def.name
        $partitioned = $def.Partitioned -eq "True"
        $enableNetBios = $def.EnableNetBIOSDomainNames -eq "True"
        
        info "Creating User Profile Service Application"
        debug "  Name:" $serviceName
        debug "  AppPool:" $def.AppPool.name
        if ($partitioned) { debug "  Partitioned" }
        
        $svcApp = Get-SPServiceApplication | ? {$_.DisplayName -eq $serviceName}
        if ($svcApp -ne $null) {
            debug "  Already exists"
            return
        }
        
        # create app pool
        $appPoolAccount = GetOrCreateManagedAccount $def.AppPool.account $config
        if ($appPoolAccount -eq $null) { throw "Managed account not found" }
        $appPool = GetOrCreateServiceApplicationPool $def.AppPool.name $appPoolAccount
        
        # create profile service
        CreateUserProfileServiceAsAdmin $def $config
        
        $svcApp = Get-SPServiceApplication | ? {$_.DisplayName -eq $serviceName}
        [int]$waitTime = 0
        while ($svcApp.Status -ne "Online") {
            if ($waitTime -gt 120) {
                warn "Timed out waiting for user profile service application to provision"
                break
            }
            sleep 1
            [int]$waitTime = $waitTime + 1
            $svcApp = Get-SPServiceApplication | ? {$_.DisplayName -eq $serviceName}
        }
        
        # create proxy
        if ($partitioned) {
            $profileServiceAppProxy = New-SPProfileServiceApplicationProxy -Name "$serviceName Proxy" -ServiceApplication $svcApp -DefaultProxyGroup -PartitionMode
            if (-not $?) { throw " - Failed to create $serviceName Proxy" }
        } else {
            $profileServiceAppProxy = New-SPProfileServiceApplicationProxy -Name "$serviceName Proxy" -ServiceApplication $svcApp -DefaultProxyGroup
            if (-not $?) { throw " - Failed to create $serviceName Proxy" }
        }
        
        # assign permissions
        ApplyPermissionsToServiceApplication $svcApp $def.Permissions $config
        ApplyAdminPermissionsToServiceApplication $svcApp $def.AdminPermissions $config
        
        # enable netbios
        # reload service app to avoid update concurrency exception
        $svcApp = Get-SPServiceApplication | ? {$_.DisplayName -eq $serviceName}
        if ($enableNetBios -eq $true) {
            debug "  enabling NetBIOS domain names"
            $svcApp.NetBIOSDomainNamesEnabled = 1
            $svcApp.Update()
        }
        
        # enable activity feed job
        debug "  Enabling Activity Feed Timer Job"
        Get-SPTimerJob | ? {$_.TypeName -eq "Microsoft.Office.Server.ActivityFeed.ActivityFeedUPAJob"} | Enable-SPTimerJob
        
        StartUserProfileService $def $config
        StartUserProfileSyncService $def $config
        
    }
}

function CreateUserProfileServiceAsAdmin($def, $config) {
    try {
        $serviceName = $def.name
        $profileDb = $def.ProfileDB
        $syncDb = $def.ProfileSyncDB
        $socialDb = $def.SocialDB
        $mySiteHostUrl = $def.MySites.HostUrl
        $personalSitePath = $def.MySites.PersonalSitePath
        $partitioned = $def.Partitioned -eq "True"
        $appPool = $def.AppPool.name
        
        $farmAcct = GetManagedAccountUsername $config.Farm.FarmSvcAccount
        [System.Management.Automation.PsCredential]$farmCredential = GetCredential $config.Farm.FarmSvcAccount $config
        
        $scriptFile = "$env:SystemDrive\tmp-upsProvision.ps1"
        
        # Write the script block, with expanded variables to a temporary script file that the Farm Account can get at
        Write-Output "Write-Host -ForegroundColor White `"Creating $serviceName as $farmAcct...`"" | Out-File $scriptFile -Width 400
        Write-Output "Add-PsSnapin Microsoft.SharePoint.PowerShell" | Out-File $scriptFile -Width 400 -Append
        if ($partitioned) {
            Write-Output "`$NewProfileServiceApp = New-SPProfileServiceApplication -Name `"$serviceName`" -PartitionMode -ApplicationPool `"$appPool`" -ProfileDBName $profileDb -ProfileSyncDBName $syncDB -SocialDBName $socialDB -MySiteHostLocation `"$mySiteHostUrl`" -MySiteManagedPath `"$personalSitePath`"" | Out-File $scriptFile -Width 400 -Append
        } else {
            Write-Output "`$NewProfileServiceApp = New-SPProfileServiceApplication -Name `"$serviceName`" -ApplicationPool `"$appPool`" -ProfileDBName $profileDb -ProfileSyncDBName $syncDB -SocialDBName $socialDB -MySiteHostLocation `"$mySiteHostUrl`" -MySiteManagedPath `"$personalSitePath`"" | Out-File $scriptFile -Width 400 -Append
        }
        Write-Output "If (-not `$?) {Write-Error `" - Failed to create $serviceName`"; Write-Host `"Press any key to exit...`"; `$null = `$host.UI.RawUI.ReadKey`(`"NoEcho,IncludeKeyDown`"`)}" | Out-File $scriptFile -Width 400 -Append
        # Start a process under the Farm Account's credentials, then spawn an elevated process within to finally execute the script file that actually creates the UPS
        Start-Process $PSHOME\powershell.exe -Credential $farmCredential -ArgumentList "-Command Start-Process $PSHOME\powershell.exe -ArgumentList `"'$scriptFile'`" -Verb Runas" -Wait
    }
    catch {
        Write-Output $_
        Pause
    } finally {
        # Delete the temporary script file if we were successful in creating the UPA
        $profileServiceApp = Get-SPServiceApplication | ? {$_.DisplayName -eq $serviceName}
        if ($profileServiceApp) {Remove-Item -Path $scriptFile -ErrorAction SilentlyContinue}
    }
}

function StartUserProfileService($def, $config) {
    # start the user profile service where necessary
    $servers = GetAllServerNamesForService "UserProfileService" $config
    
    # start this service on all severs specified
    if ($servers -ne "none") {
        info "Starting User Profile Service on $servers"
        StartServiceOnServers "Microsoft.Office.Server.Administration.UserProfileServiceInstance" $servers
    }
    
    # now stop this service everywhere else
    $allServers = GetAllServerNames $config
    foreach ($server in $allServers) {
        info "Ensuring User Profile Service is stopped on all other servers"
        if ($servers -notcontains $server) {
            StopService "Microsoft.Office.Server.Administration.UserProfileServiceInstance" $server
        }
    }
}

function StartUserProfileSyncService($def, $config) {
    # start sync service
    $syncServer = GetAllServerNamesForService "UserProfileSyncService" $config
    if ($syncServer.Count -gt 1) {
        $syncServer = $syncServer[0]
    }
    
    $farmAcct = GetManagedAccountUsername $config.Farm.FarmSvcAccount $config
    $farmAcctPwd = GetManagedAccountPassword $config.Farm.FarmSvcAccount $config
    
    $syncService = GetServiceInstance "Microsoft.Office.Server.Administration.ProfileSynchronizationServiceInstance" $syncServer
    
    debug "  starting user profile sync service on server" $syncServer
    
    $svcApp.SetSynchronizationMachine($syncServer, [Guid]$syncService.Id, $farmAcct, $farmAcctPwd)
    [int]$iterations = 0
    while ($syncService.Status -ne "Online") {
        if ($iterations -gt 600) {
            warn "Could not start user profile synchronization service.  Please configure manually"
            break
        }
        show-progress
        sleep 1
        [int]$iterations = $iterations + 1
        $syncService = GetServiceInstance "Microsoft.Office.Server.Administration.ProfileSynchronizationServiceInstance" $syncServer
    }
    
    debug "  restarting IIS"
    Start-Process -FilePath iisreset.exe -ArgumentList "-noforce" -Wait -NoNewWindow
}

# ---------------------------------------------------------------
# Secure Store
# ---------------------------------------------------------------

function ProvisionSecureStoreServiceApplications($config) {
    if ($config.ServiceApplications.SecureStoreApplication -eq $null) {
        return
    }
    
    foreach ($def in $config.ServiceApplications.SecureStoreApplication) {
        $serviceApp = Get-SPServiceApplication -Name $def.name -ErrorAction SilentlyContinue
        if ($serviceApp -eq $null) {
            info "Creating secure store application" $def.name
            $dbName = $def.DBName
            $createCmd = "New-SPSecureStoreServiceApplication -Sharing:`$false -DatabaseName `"$dbName`" -AuditingEnabled:`$true -AuditLogMaxSize 30"
            if ($partitioned) { $createCmd += " -PartitionMode" }
            
            $proxyCmd = "New-SPSecureStoreServiceApplicationProxy -DefaultProxyGroup"
            if ($partitioned) { $proxyCmd += " -PartitionMode" }
            
            ProvisionServiceApplication $def $createCmd $proxyCmd $config
            
            # set key
            $proxy = Get-SPServiceApplicationProxy | where { $_.DisplayName -eq $def.name + " Proxy" }
            Update-SPSecureStoreMasterKey -ServiceApplicationProxy $proxy.Id -Passphrase $config.Farm.Passphrase
            Update-SPSecureStoreApplicationServerKey -ServiceApplicationProxy $proxy.Id -Passphrase $config.Farm.Passphrase
        }
    }
}

# ---------------------------------------------------------------
# State Service
# ---------------------------------------------------------------

function ProvisionStateServiceApplications($config) {
    if ($config.ServiceApplications.StateServiceApplication -eq $null) {
        return
    }
    
    foreach ($def in $config.ServiceApplications.StateServiceApplication) {
        $existingApp = Get-SPStateServiceApplication -Identity $def.name -ErrorAction SilentlyContinue
        if ($existingApp -eq $null) {
            info "Creating state service application" $def.name
            New-SPStateServiceDatabase -Name $def.DBName | Out-Null
            $app = New-SPStateServiceApplication -Name $def.name -Database $def.DBName
            Get-SPStateServiceDatabase | Initialize-SPStateServiceDatabase | Out-Null
            
            $proxyName = $def.name + " Proxy"
            $app | New-SPStateServiceApplicationProxy -Name $proxyName -DefaultProxyGroup | Out-Null
        }
    }
}

# ---------------------------------------------------------------
# Web Analytics Service
# ---------------------------------------------------------------

function ProvisionWebAnalyticsServiceApplications($config) {
    if ($config.ServiceApplications.WebAnalyticsApplication -eq $null) {
        return
    }
    
    foreach ($def in $config.ServiceApplications.WebAnalyticsApplication) {
        $existingApp = Get-SPWebAnalyticsServiceApplication $def.name -ErrorAction SilentlyContinue
        if ($existingApp -eq $null) {
            info "Creating new web analytics application" $def.name
            $dbServer = $config.Farm.DatabaseServer
            $stagingDb = $def.StagingDB
            $reportingDb = $def.ReportingDB
            $stagingDbList = "<StagingDatabases><StagingDatabase ServerName='$dbServer' DatabaseName='$stagingDb'/></StagingDatabases>"
            $reportingDbList ="<ReportingDatabases><ReportingDatabase ServerName='$dbServer' DatabaseName='$reportingDb'/></ReportingDatabases>"
            $dataRetention = $def.DataRetentionPeriod
            $samplingRate = $def.SamplingRate
            
            $createCmd = "New-SPWebAnalyticsServiceApplication -ReportingDataRetention $dataRetention -SamplingRate $samplingRate -ListOfReportingDatabases `"$reportingDbList`" -ListOfStagingDatabases `"$stagingDbList`""
            
            $proxyCmd = "New-SPWebAnalyticsServiceApplicationProxy"
            
            ProvisionServiceApplication $def $createCmd $proxyCmd $config
        }
    }
}

# ---------------------------------------------------------------
# WSS Usage
# ---------------------------------------------------------------

function ProvisionWSSUsageServiceApplications($config) {
    if ($config.ServiceApplications.WSSUsageApplication -eq $null) {
        return
    }
    
    foreach ($def in $config.ServiceApplications.WSSUsageApplication) {
        $existingApp = Get-SPUsageApplication
        if ($existingApp -eq $null) {
            info "Creating new WSS USage App"
            New-SPUsageApplication -Name $def.name -DatabaseName $def.DBName | Out-Null
            $proxy = Get-SPServiceApplicationProxy | where {$_.DisplayName -eq $def.name}
            $proxy.Provision()
        }
    }
}

# ---------------------------------------------------------------
# BDC
# ---------------------------------------------------------------

function ProvisionBusinessDataConnectivityApplications($config) {
    if ($config.ServiceApplications.BusinessDataConnectivityApplication -eq $null) {
        return
    }
    
    foreach ($def in $config.ServiceApplications.BusinessDataConnectivityApplication) {
        $existingApp = Get-SPServiceApplication | where {$_.DisplayName -eq $def.name}
        if ($existingApp -eq $null) {
            info "Creating business data application" $def.name
            
            $dbName = $def.DBName
            $partitioned = $def.Partitioned -eq "True"
            
            $createCmd = "New-SPBusinessDataCatalogServiceApplication -DatabaseName `"$dbName`""
            if ($partitioned) { $createCmd += " -PartitionMode" }
            
            ProvisionServiceApplication $def $createCmd "" $config
        }
    }
}

# ---------------------------------------------------------------
# Access Services
# ---------------------------------------------------------------

function ProvisionAccessServicesApplications($config) {
    if ($config.ServiceApplications.AccessServicesApplication -eq $null) {
        return
    }
    
    foreach ($def in $config.ServiceApplications.AccessServicesApplication) {
        $existingApp = Get-SPAccessServiceApplication -Identity $def.name -ErrorAction SilentlyContinue
        if ($existingApp -eq $null) {
            info "Creating access services application" $def.name
            
            $createCmd = "New-SPAccessServiceApplication"
            
            ProvisionServiceApplication $def $createCmd "" $config
        }
    }
}

# ---------------------------------------------------------------
# Visio Graphics Services
# ---------------------------------------------------------------

function ProvisionVisioGraphicsApplications($config) {
    if ($config.ServiceApplications.VisioGraphicsApplication -eq $null) {
        return
    }
    
    foreach ($def in $config.ServiceApplications.VisioGraphicsApplication) {
        $existingApp = Get-SPServiceApplication | where {$_.DisplayName -eq $def.name}
        if ($existingApp -eq $null) {
            info "Creating visio graphics application" $def.name
            
            # Get or create app pool
            $appPoolName = $def.AppPool.name
            $appPoolAccount = GetOrCreateManagedAccount $def.AppPool.account $config
            if ($appPoolAccount -eq $null) { throw "Managed account not found" }
            
            $appPool = GetOrCreateServiceApplicationPool $appPoolName $appPoolAccount
            
            debug "  creating service application"
            $serviceApp = New-SPVisioServiceApplication -Name $def.name -ApplicationPool $appPool
            
            debug "  creating proxy"
            New-SPVisioServiceApplicationProxy -Name "$($def.name) Proxy" -ServiceApplication $def.name | out-null
            
            ApplyPermissionsToServiceApplication $serviceApp $def.Permissions $config
            ApplyAdminPermissionsToServiceApplication $serviceApp $def.AdminPermissions $config
        }
    }
}

# ---------------------------------------------------------------
# Utility Functions
# ---------------------------------------------------------------

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
            $serviceAppCmd += " -Name `$appName -ApplicationPool `$appPool"
            $createAppCmd = $ExecutionContext.InvokeCommand.NewScriptBlock($serviceAppCmd)
            $serviceApp = Invoke-Command -ScriptBlock $createAppCmd
            if (-not $?) { throw "- Failed to create service application" }
            
            # create proxy
            if ($proxyCmd -ne "") {
                debug "  Creating application proxy..."
                $proxyCmd += " -Name `"$appName Proxy`" -ServiceApplication `$serviceApp"
                $createProxyCmd = $ExecutionContext.InvokeCommand.NewScriptBlock($proxyCmd)
                Invoke-Command -ScriptBlock $createProxyCmd | Out-Null
                if (-not $?) { throw "- Failed to create service application proxy" }
            }
            
            # assign permissions
            ApplyPermissionsToServiceApplication $serviceApp $appDefinition.Permissions $config
            ApplyAdminPermissionsToServiceApplication $serviceApp $appDefinition.AdminPermissions $config
            
            debug "  done"
            
        } else {
            debug "Service application already exists"
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
    if ($permissions -eq $null) {
        return
    }

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

function ApplyAdminPermissionsToServiceApplication($serviceAppToSecure, $permissions, $config) {
    if ($permissions -eq $null) {
        return
    }

    ## Get ID of "Service"
    $serviceAppIDToSecure = $serviceAppToSecure.Id
    
    ## Get security for app
    $serviceAppSecurity = Get-SPServiceApplicationSecurity $serviceAppIDToSecure -Admin
            
    ## Get the Claims Principals for each identity specified
    foreach ($perm in $permissions.Grant) {
        $identity = GetManagedAccountUsername $perm.account $config
        $principal = New-SPClaimsPrincipal -Identity $identity -IdentityType WindowsSamAccountName
        Grant-SPObjectSecurity $serviceAppSecurity -Principal $principal -Rights $perm.rights
    }
    
    ## Apply the changes to the Service application
    Set-SPServiceApplicationSecurity $serviceAppIDToSecure -objectSecurity $serviceAppSecurity -Admin
}
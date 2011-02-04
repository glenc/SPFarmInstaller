# ---------------------------------------------------------------
# Topology Functions
# ---------------------------------------------------------------

function ConfigureTopology($config) {

    ConfigureBulkServices $config
    ConfigureWFEServers $config
    ConfigureDocLoadBalancing $config
    
}

function ConfigureBulkServices($config) {
    # All services and their associated type.  This serves two purposes:
    #  first, it provides a link between the friendly name and the full type name
    #  it serves as the list of services which can be blindly started on a server
    #  without additional configuration
    $services = @{
        "AccessService" = "Microsoft.Office.Access.Server.MossHost.AccessServerWebServiceInstance";
        "ExcelCalculationServices" = "Microsoft.Office.Excel.Server.MossHost.ExcelServerWebServiceInstance";
        "PerformancePoint" = "Microsoft.PerformancePoint.Scorecards.BIMonitoringServiceInstance";
        "VisioGraphics" = "Microsoft.Office.Visio.Server.Administration.VisioGraphicsServiceInstance";
        "WordAutomation" = "Microsoft.Office.Word.Server.Service.WordServiceInstance";
        "ApplicationRegistryService" = "Microsoft.Office.Server.ApplicationRegistry.SharedService.ApplicationRegistryServiceInstance";
        "BusinessDataConnectivityService" = "Microsoft.SharePoint.BusinessData.SharedService.BdcServiceInstance";
        "DocumentConversionsLoadBalancer" = "Microsoft.Office.Server.Conversions.LoadBalancerServiceInstance";
        "SearchQueryAndSiteSettings" = "Microsoft.Office.Server.Search.Administration.SearchQueryAndSiteSettingsServiceInstance";
        "SecureStore" = "Microsoft.Office.SecureStoreService.Server.SecureStoreServiceInstance";
        "SubscriptionSettings" = "Microsoft.SharePoint.SPSubscriptionSettingsServiceInstance";
        "SandboxedCode" = "Microsoft.SharePoint.Administration.SPUserCodeServiceInstance";
        "ManagedMetadata" = "Microsoft.SharePoint.Taxonomy.MetadataWebServiceInstance";
        "UserProfileService" = "Microsoft.Office.Server.Administration.UserProfileServiceInstance";
        "WebAnalyticsWebService" = "Microsoft.Office.Server.WebAnalytics.Administration.WebAnalyticsWebServiceInstance";
        "WebAnalyticsDataProcessing" = "Microsoft.Office.Server.WebAnalytics.Administration.WebAnalyticsServiceInstance";
        "IncomingEmail" = "Microsoft.SharePoint.Administration.SPIncomingEmailServiceInstance";
        "SharePointSearch" = "Microsoft.SharePoint.Search.Administration.SPSearchServiceInstance";
        "WorkflowTimerService" = "Microsoft.SharePoint.Workflow.SPWorkflowTimerServiceInstance";
        "ClaimsToWindowsTokenService" = "Microsoft.SharePoint.Administration.Claims.SPWindowsTokenServiceInstance"
        
        # these services cannot be provisined here because they require configuration
        #"DocumentConversionsLauncher" = "Microsoft.Office.Server.Conversions.LauncherServiceInstance";
        #"UserProfileSyncService" = "Microsoft.Office.Server.Administration.ProfileSynchronizationServiceInstance";
        #"WebApplication" = "Microsoft.SharePoint.Administration.SPWebServiceInstance";
        #"LotusNotesConnector" = "Microsoft.Office.Server.Search.Administration.NotesWebServiceInstance";
        
    }
    
    $topology = $config.Topology
    foreach ($key in $services.Keys) {
        $serviceDef = $topology.Service | Where-Object { $_.name -eq $key }
        if ($serviceDef -ne $null) {
            $servers = GetServerNames $serviceDef.runningOn $config
            
            # start this service on all severs specified
            if ($servers -ne "none") {
                info "Starting $key on $servers"
                StartServiceOnServers $services.Get_Item($key) $servers
            }
            
            # now stop this service everywhere else
            $allServers = GetAllServerNames $config
            foreach ($server in $allServers) {
                info "Ensuring $key is stopped on all other servers"
                if ($servers -notcontains $server) {
                    StopService $services.Get_Item($key) $server
                }
            }
        }
    }
}

function ConfigureWFEServers($config) {
    # handle WFE role - handle this special to avoid stopping/starting central admin
    # which has the same class name as WFE
    $wfeServiceDef = $config.Topology.Service | Where-Object { $_.name -eq "WebApplication" }
    if ($wfeServiceDef -ne $null) {
        $wfeType = "Microsoft.SharePoint.Administration.SPWebServiceInstance"
        $centralAdminName = "Central Administration"
    
        $wfeServers = GetServerNames $wfeServiceDef.runningOn $config
        $allServers = GetAllServerNames $config
        
        info "Starting WebApplication service on $wfeServers"
        foreach ($server in $wfeServers) {
            $services = Get-SPServiceInstance -Server $server | ? {$_.GetType().ToString() -eq $wfeType -and $_.TypeName -ne $centralAdminName}
            foreach ($svc in $services) {
                debug "  Starting service WebApplication on server", $server
                StartServiceInstance $svc
            }
        }
        
        info "Ensuring WebApplication service is stopped on all other servers"
        foreach ($server in $allServers) {
            if ($wfeServers -notcontains $server) {
                $services = Get-SPServiceInstance -Server $server | ? {$_.GetType().ToString() -eq $wfeType -and $_.TypeName -ne $centralAdminName}
                foreach ($svc in $services) {
                    debug "  Stopping service WebApplication on server", $server
                    StopServiceInstance $svc
                }
            }
        }
    }
}

function ConfigureDocLoadBalancing($config) {
    
}

function GetServerNames([string]$reference, $config) {
    $serverNames = @()
    $refNames = $reference.Split(",")
    $refNames | foreach {
        $nm = $_.Trim()
        if ($config.Topology.ServerGroups -ne $null) {
            $group = $config.Topology.ServerGroups.Group | Where-Object { $_.name -eq $nm }
        }
        if ($group -eq $null) {
            $serverNames += $nm
        } else {
            $group.Server | foreach { $serverNames += $_.name }
        }
    }
    return $serverNames
}

function GetAllServerNames($config) {
    $tmpNames = $config.SelectNodes("Topology/ServerGroups/Group/Server/@name | Topology/Service/@runningOn") | Select-Object Value -Unique
    $names = @()
    foreach($n in $tmpNames) {
        $names += GetServerNames $n.Value $config
    }
    $names = $names | ? {$_ -ne "none"} | Sort-Object | Get-Unique
    return $names
}

function StartService([string]$service, [string]$server) {
    $tmp = $service.Split(".")
    $shortName = $tmp[$tmp.Length - 1]
    debug "  Starting service", $shortName, "on server", $server
    $svc = GetServiceInstance $service $server
    
    if ($svc -eq $null) {
        warn "Could not get service instance on server $server"
        return
    }
    
    StartServiceInstance $svc
}

function StartServiceInstance($instance) {
    if ($instance.Status.ToString() -eq "Disabled") {
        try {
            $instance | Start-SPServiceInstance | Out-Null
            if (-not $?) { throw "Failed to start service" }
        } catch {
            warn "An error occurred starting service"
        }
        
        # wait for service to start
        debug "  Waiting for service to start"
        while ($instance.Status -ne "Online") {
            show-progress
            sleep 1
            $instance = Get-SPServiceInstance | ? { $_.Id -eq $instance.Id }
        }
        debug "  Started!"
    } else {
        debug "  Already started"
    }
}

function StartServiceOnServers([string]$service, $servers) {
    foreach ($server in $servers) {
        StartService $service $server
    }
}

function StartServiceOnLocal([string]$service) {
    StartService $service
}

function StopService([string]$service, [string]$server) {
    $tmp = $service.Split(".")
    $shortName = $tmp[$tmp.Length - 1]
    debug "  Stopping service", $shortName, "on server", $server
    $svc = GetServiceInstance $service $server
    
    if ($svc -eq $null) {
        warn "Could not get service instance on server $server"
        return
    }
    
    StopServiceInstance $svc
}

function StopServiceInstance($instance) {
    if ($instance.Status.ToString() -eq "Online") {
        try {
            $instance | Stop-SPServiceInstance -Confirm:$false | Out-Null
            if (-not $?) { throw "Failed to stop service" }
        } catch {
            warn "An error occurred stopping service"
        }
        
        # wait for service to start
        debug "  Waiting for service to stop"
        while ($instance.Status -ne "Disabled") {
            show-progress
            sleep 1
            $instance = Get-SPServiceInstance | ? { $_.Id -eq $instance.Id }
        }
        debug "  Stopped!"
    } else {
        debug "  Already Stopped"
    }
}

function StopServiceOnServers([string]$service, $servers) {
    foreach ($server in $servers) {
        StopService $service $server
    }
}

function StopServiceOnLocal([string]$service) {
    StopService $service
}

function GetServiceInstance([string]$service, [string]$server) {
    $found = $null
    if ($server -eq $null -or $server -eq "localhost") {
        $found = Get-SPServiceInstance | ? {$_.GetType().ToString() -eq $service}
    } else {
        $found = Get-SPServiceInstance -Server $server | ? {$_.GetType().ToString() -eq $service}
    }
    
    if ($found -eq $null -or $found.Count -eq 0) {
        return $null
    }
    
    if ($found.Count -ge 1) {
        return $found[0]
    } else {
        return $found
    }
}
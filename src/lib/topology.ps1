# ---------------------------------------------------------------
# Topology Functions
# ---------------------------------------------------------------

function ConfigureTopology($config) {
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
        #"DocumentConversionsLauncher" = "Microsoft.Office.Server.Conversions.LauncherServiceInstance";
        #"DocumentConversionsLoadBalancer" = "Microsoft.Office.Server.Conversions.LoadBalancerServiceInstance";
        "LotusNotesConnector" = "Microsoft.Office.Server.Search.Administration.NotesWebServiceInstance";
        "SearchQueryAndSiteSettings" = "Microsoft.Office.Server.Search.Administration.SearchQueryAndSiteSettingsServiceInstance";
        "SecureStore" = "Microsoft.Office.SecureStoreService.Server.SecureStoreServiceInstance";
        "SubscriptionSettings" = "Microsoft.SharePoint.SPSubscriptionSettingsServiceInstance";
        "SandboxedCode" = "Microsoft.SharePoint.Administration.SPUserCodeServiceInstance";
        "ManagedMetadata" = "Microsoft.SharePoint.Taxonomy.MetadataWebServiceInstance";
        "UserProfileService" = "Microsoft.Office.Server.Administration.UserProfileServiceInstance";
        "UserProfileSyncService" = "Microsoft.Office.Server.Administration.ProfileSynchronizationServiceInstance";
        "WebAnalyticsWebService" = "Microsoft.Office.Server.WebAnalytics.Administration.WebAnalyticsWebServiceInstance";
        "WebAnalyticsDataProcessing" = "Microsoft.Office.Server.WebAnalytics.Administration.WebAnalyticsServiceInstance";
        "IncomingEmail" = "Microsoft.SharePoint.Administration.SPIncomingEmailServiceInstance";
        "SharePointSearch" = "Microsoft.SharePoint.Search.Administration.SPSearchServiceInstance";
        "WebApplication" = "Microsoft.SharePoint.Administration.SPWebServiceInstance";
        "WorkflowTimerService" = "Microsoft.SharePoint.Workflow.SPWorkflowTimerServiceInstance";
        "ClaimsToWindowsTokenService" = "Microsoft.SharePoint.Administration.Claims.SPWindowsTokenServiceInstance"
    }
    
    $topology = $config.Topology
    foreach ($key in $services.Keys) {
        $serviceDef = $topology.Service | Where-Object { $_.name -eq $key }
        if ($serviceDef -ne $null) {
            $servers = GetServerNames $serviceDef.runningOn $config
            if ($servers -ne "none") {
                info "Starting $key on $servers"
                StartServiceOnServers $services.Get_Item($key) $servers
            }
        }
    }
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

function StartService([string]$service, [string]$server) {
    debug "  Starting service", $service, "on server", $server
    $svc = GetServiceInstance $service $server
    
    if ($svc -eq $null) {
        warn "Could not get service instance on server $server"
        return
    }
    
    if ($svc.Status.ToString() -eq "Disabled") {
        try {
            $svc | Start-SPServiceInstance | Out-Null
            if (-not $?) { throw "Failed to start service" }
        } catch {
            warn "An error occurred starting service"
        }
        
        # wait for service to start
        debug "  Waiting for service to start"
        while ($svc.Status -ne "Online") {
            show-progress
            sleep 1
            $svc = GetServiceInstance $service $server
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
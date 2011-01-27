# ---------------------------------------------------------------
# Topology Functions
# ---------------------------------------------------------------

function StartService([string]$service, [string]$server) {
    info "Starting service", $service, "on server", $server
    $svc = GetServiceInstance $service $server
    if ($svc.Status -eq "Disabled") {
        try {
            debug "Got service, attempt to start..."
            $svc | Start-SPServiceInstance | Out-Null
            if (-not $?) { throw "Failed to start service" }
        } catch {
            "An error occurred starting service"
        }
        
        # wait for service to start
        debug "Waiting for service to start"
        while ($svc.Status -ne "Online") {
            show-progress
            sleep 1
            $svc = GetServiceInstance $service $server
        }
        debug "Started!"
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
    if ($server -eq $null) {
        return Get-SPServiceInstance | ? {$_.GetType().ToString() -eq $service}
    } else {
        return Get-SPServiceInstance -Server $server | ? {$_.GetType().ToString() -eq $service}
    }
}

function ConfigureTopology($topology) {
    # names of specific services
    $keys = @{
        "SandboxSolution"    = "Microsoft.SharePoint.Administration.SPUserCodeServiceInstance";
        "ManagedMetadata"    = "Microsoft.SharePoint.Taxonomy.MetadataWebServiceInstance";
        "UserProfileService" = "Microsoft.Office.Server.Administration.UserProfileServiceInstance";
        #"SearchQueryAndSiteSettings" = "Microsoft.Office.Server.Search.Administration.SearchQueryAndSiteSettingsServiceInstance"
    }
    
    foreach ($key in $keys.Keys) {
        if ($topology.ContainsKey($key + "Servers")) {
            $servers = $topology.Get_Item($key + "Servers")
            $service = $keys.Get_Item($key)
            StartServiceOnServers $service $servers
        }
    }
    
    # also provision the following on all WFE servers
    $wfeServers = $topology.Get_Item("WebFrontEndServers")
    StartServiceOnServers "Microsoft.Office.Server.Search.Administration.SearchQueryAndSiteSettingsServiceInstance" $wfeServers
}
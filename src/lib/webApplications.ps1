# ---------------------------------------------------------------
# Web Application Functions
# ---------------------------------------------------------------

function ProvisionWebApplications($config) {
    if ($config.WebApplications.WebApplication -eq $null) {
        return
    }
    
    foreach ($def in $config.WebApplications.WebApplication) {
        $webapp = Get-SPWebApplication | Where-Object {$_.DisplayName -eq $def.name}
        if ($webapp -eq $null) {
            CreateWebApplication $def $config
        }
    }
}

function CreateWebApplication($def, $config) {
    try {
        debug "  Creating new web app" $def.name
        $useSSL = $def.Url -like "https://*"
        if ($useSSL) { $protocol = "https://" } else { $protocol = "http://" }
        
        $tmp = $def.Url -replace $protocol,""
        $parts = $tmp -split ":"
        [string]$hostHeader = $parts[0]
        if ($parts.Count -eq 2) {
            $port = $parts[1]
        } else {
            $port = 80
        }
        
        debug "  Protocol:" $protocol "Host:" $hostHeader "Port:" $port
        
        $appPoolAccount = GetOrCreateManagedAccount $def.AppPool.account $config
        $anonymous = $def.Authentication.allowAnonymous -eq "True"
        $useClaims = $def.Authentication.mode -eq "Claims"
        
        if ($useClaims) {
            debug "  Creating web app with claims"
            $authProvider = New-SPAuthenticationProvider -UseWindowsIntegratedAuthentication
            New-SPWebApplication -Name $def.name `
                                 -ApplicationPoolAccount $appPoolAccount `
                                 -ApplicationPool $def.AppPool.name `
                                 -DatabaseName $def.ContentDatabase `
                                 -HostHeader $hostHeader `
                                 -Url $def.Url `
                                 -Port $port `
                                 -SecureSocketsLayer:$useSSL `
                                 -AuthenticationMethod $def.Authentication.method `
                                 -AllowAnonymousAccess:$anonymous `
                                 -AuthenticationProvider $authProvider | out-null
            if (-not $?) { throw "Failed to create web application" }
        } else {
            debug "  Creating web app in classic mode"
            New-SPWebApplication -Name $def.name `
                                 -ApplicationPoolAccount $appPoolAccount `
                                 -ApplicationPool $def.AppPool.name `
                                 -DatabaseName $def.ContentDatabase `
                                 -HostHeader $hostHeader `
                                 -Url $def.Url `
                                 -Port $port `
                                 -SecureSocketsLayer:$useSSL `
                                 -AuthenticationMethod $def.Authentication.method `
                                 -AllowAnonymousAccess:$anonymous | out-null
            if (-not $?) { throw "Failed to create web application" }
        }
        
        # set up managed paths
        DefineManagedPaths $def $config
        
        # create site collections
        CreateSiteCollections $def $config
        
    } catch {
        Write-Output $_
    }
}

function DefineManagedPaths($def, $config) {
    # first remove existing ones
    $paths = Get-SPManagedPath -WebApplication $def.Url | Where-Object {$_.Name -ne ""}
    foreach ($path in $paths) {
        debug "  removing managed path" $path.Name
        Remove-SPManagedPath -Identity $path.Name -WebApplication $def.Url -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    }
    
    # now add new ones
    if ($def.ManagedPaths.ManagedPath -ne $null) {
        foreach ($newPath in $def.ManagedPaths.ManagedPath) {
            debug "  adding managed path" $newPath.path
            if ($newPath.type -like "Explicit*") {
                New-SPManagedPath -RelativeUrl $newPath.path -WebApplication $def.Url -Explicit -ErrorAction SilentlyContinue | Out-Null
            } else {
                New-SPManagedPath -RelativeUrl $newPath.path -WebApplication $def.Url -ErrorAction SilentlyContinue | Out-Null
            }
        }
    }
}

function CreateSiteCollections($def, $config) {
    if ($def.SiteCollections.SiteCollection -eq $null) {
        return
    }
    
    foreach ($siteDef in $def.SiteCollections.SiteCollection) {
        debug "  creating site collection" $siteDef.url
        New-SPSite  -Url $siteDef.url `
                    -OwnerAlias $siteDef.owner `
                    -Name $siteDef.name `
                    -Description $siteDef.description `
                    -Language $siteDef.lcid `
                    -Template $siteDef.template | Out-Null
    }
}
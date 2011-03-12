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
            if ($useSSL) {
                $port = 443
            } else {
                $port = 80
            }
        }
        
        debug "  Protocol:" $protocol "Host:" $hostHeader "Port:" $port
        
        $appPoolAccount = GetOrCreateManagedAccount $def.AppPool.account $config
        $anonymous = $def.Authentication.allowAnonymous -eq "True"
        $useClaims = $def.Authentication.mode -eq "Claims"
        $webAppUrl = $protocol + $hostHeader
        
        if ($useClaims) {
            debug "  Creating web app with claims"
            $authProvider = New-SPAuthenticationProvider -UseWindowsIntegratedAuthentication
            New-SPWebApplication -Name $def.name `
                                 -ApplicationPoolAccount $appPoolAccount `
                                 -ApplicationPool $def.AppPool.name `
                                 -DatabaseName $def.ContentDatabase `
                                 -HostHeader $hostHeader `
                                 -Url $webAppUrl `
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
                                 -Url $webAppUrl `
                                 -Port $port `
                                 -SecureSocketsLayer:$useSSL `
                                 -AuthenticationMethod $def.Authentication.method `
                                 -AllowAnonymousAccess:$anonymous | out-null
            if (-not $?) { throw "Failed to create web application" }
        }
        
        # assign cert
        if ($useSSL) {
            AssignCert $hostHeader $port $config
        }
        
        # set up managed paths
        DefineManagedPaths $def $config
        
        # create site collections
        CreateSiteCollections $def $config
        
        # apply cache account
        ConfigureObjectCache $def
        
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

function AssignCert($SSLHostHeader, $SSLPort, $config){
    # Load IIS WebAdministration Snapin/Module
    # Inspired by http://stackoverflow.com/questions/1924217/powershell-load-webadministration-in-ps1-script-on-both-iis-7-and-iis-7-5
    $QueryOS = Gwmi Win32_OperatingSystem
    $QueryOS = $QueryOS.Version 
    $OS = ""
    if ($QueryOS.contains("6.1")) {$OS = "Win2008R2"}
    elseif ($QueryOS.contains("6.0")) {$OS = "Win2008"}
    
    $bits = $config.Installation.PathToBits
    
    try {
        if ($OS -eq "Win2008") {
            if (!(Get-PSSnapin WebAdministration -ErrorAction SilentlyContinue)) {     
                  if (!(Test-Path $env:ProgramFiles\IIS\PowerShellSnapin\IIsConsole.psc1)) {
                    Start-Process -Wait -NoNewWindow -FilePath msiexec.exe -ArgumentList "/i `"$bits\PrerequisiteInstallerFiles\iis7psprov_x64.msi`" /passive /promptrestart"
                }
                Add-PSSnapin WebAdministration
            }
        }
        else { 
              Import-Module WebAdministration
        }
    } catch {
        info "  Could not load IIS Administration module."
    }
    debug "  Assigning certificate to site `"https://$SSLHostHeader`:$SSLPort`""
    debug "  Looking for existing `"$SSLHostHeader`" certificate to use..."
    $Cert = Get-ChildItem cert:\LocalMachine\My | ? {$_.Subject -eq "CN=$SSLHostHeader"}
    if (!$Cert) {
        debug "  None found."
        $MakeCert = "$env:ProgramFiles\Microsoft Office Servers\14.0\Tools\makecert.exe"
        if (Test-Path "$MakeCert") {
            debug "  Creating new self-signed certificate..."
            Start-Process -NoNewWindow -Wait -FilePath "$MakeCert" -ArgumentList "-r -pe -n `"CN=$SSLHostHeader`" -eku 1.3.6.1.5.5.7.3.1 -ss My -sr localMachine -sky exchange -sp `"Microsoft RSA SChannel Cryptographic Provider`" -sy 12"
            $Cert = Get-ChildItem cert:\LocalMachine\My | ? {$_.Subject -eq "CN=$SSLHostHeader"}
            $CertSubject = $Cert.Subject
        } else {
            debug "  `"$MakeCert`" not found."
            debug "  Looking for any machine-named certificates we can use..."
            # Select the first certificate with the most recent valid date
            $Cert = Get-ChildItem cert:\LocalMachine\My | ? {$_.Subject -like "*$env:COMPUTERNAME"} | Sort-Object NotBefore -Desc | Select-Object -First 1
            if (!$Cert) {
                warn "  No cert found, skipping certificate creation."
            } else {
                $CertSubject = $Cert.Subject
            }
        }
    } else {
        $CertSubject = $Cert.Subject
        debug "  Certificate `"$CertSubject`" found."
    }
    if ($Cert) {
        # Export our certificate to a file, then import it to the Trusted Root Certification Authorites store so we don't get nasty browser warnings
        # This will actually only work if the Subject and the host part of the URL are the same
        # Borrowed from https://www.orcsweb.com/blog/james/powershell-ing-on-windows-server-how-to-import-certificates-using-powershell/
        debug "  Exporting `"$CertSubject`" to `"$SSLHostHeader.cer`"..."
        $Cert.Export("Cert") | Set-Content "$env:TEMP\$SSLHostHeader.cer" -Encoding byte
        $Pfx = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
        debug "  Importing `"$SSLHostHeader.cer`" to Local Machine\Root..."
        $Pfx.Import("$env:TEMP\$SSLHostHeader.cer")
        $Store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root","LocalMachine")
        $Store.Open("MaxAllowed")
        $Store.Add($Pfx)
        $Store.Close()
        debug "  Assigning certificate `"$CertSubject`" to SSL-enabled site..."
        #Set-Location IIS:\SslBindings -ErrorAction Inquire
        $Cert | New-Item IIS:\SslBindings\0.0.0.0!$SSLPort -ErrorAction Inquire | Out-Null
        debug "  Certificate has been assigned to site `"https://$SSLHostHeader`:$SSLPort`""
    } else {
        warn "No certificates were found, and none could be created."
    }
    $Cert = $null
}

function ConfigureObjectCache($def) {
    try {
           $url = $def.Url
        $wa = Get-SPWebApplication | Where-Object {$_.DisplayName -eq $def.name}
        $superUserAcc = $def.ObjectCacheAccounts.SuperUser
        $superReaderAcc = $def.ObjectCacheAccounts.SuperReader
        
        # If the web app is using Claims auth, change the user accounts to the proper syntax
        if ($wa.UseClaimsAuthentication -eq $true) {
            $superUserAcc = 'i:0#.w|' + $superUserAcc
            $superReaderAcc = 'i:0#.w|' + $superReaderAcc
        }
        
        debug "  Applying object cache accounts to `"$url`"..."
        $wa.Properties["portalsuperuseraccount"] = $superUserAcc
        SetWebAppUserPolicy $wa $superUserAcc "Super User (Object Cache)" "Full Control"
        
        $wa.Properties["portalsuperreaderaccount"] = $superReaderAcc
        SetWebAppUserPolicy $wa $superReaderAcc "Super Reader (Object Cache)" "Full Read"
        $wa.Update()        
        
        debug "  Done applying object cache accounts to `"$url`""
    } catch {
        $_
        warn "  An error occurred applying object cache to `"$url`""
        Pause
    }
}

function SetWebAppUserPolicy($wa, $userName, $displayName, $perm) {
    [Microsoft.SharePoint.Administration.SPPolicyCollection]$policies = $wa.Policies
    [Microsoft.SharePoint.Administration.SPPolicy]$policy = $policies.Add($userName, $displayName)
    [Microsoft.SharePoint.Administration.SPPolicyRole]$policyRole = $wa.PolicyRoles | where {$_.Name -eq $perm}
    if ($policyRole -ne $null) {
        $policy.PolicyRoleBindings.Add($policyRole)
    }
    $wa.Update()
}
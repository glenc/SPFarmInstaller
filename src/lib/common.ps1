# ---------------------------------------------------------------
# Common Functions
# ---------------------------------------------------------------
# This script contains common functions used by other scripts
# in the installers
# ---------------------------------------------------------------

# enable SP Add-ins
if ((Get-PsSnapin |?{$_.Name -eq "Microsoft.SharePoint.PowerShell"})-eq $null) {
   	$PSSnapin = Add-PsSnapin Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue | Out-Null
}

# General Functions
function Pause {
	#From http://www.microsoft.com/technet/scriptcenter/resources/pstips/jan08/pstip0118.mspx
	Write-Host "Press any key to exit..."
	$null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Logging Functions
function global:info {
    Write-Host -ForegroundColor Black $args
}

function global:debug {
    Write-Host -ForegroundColor Gray $args
}

function global:error {
    Error $args
}

function global:warn {
    Write-Warning $args
}

function global:show-progress {
    Write-Host -ForegroundColor Blue "." -NoNewLine
}

# SharePoint Service Functions
function global:StartService([string]$service, [string]$server) {
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

function global:StartServiceOnServers([string]$service, [System.Array]$servers) {
    foreach ($server in $servers) {
        StartService $service $server
    }
}

function global:StartServiceOnLocal([string]$service) {
    StartService $service
}

function global:GetServiceInstance([string]$service, [string]$server) {
    if ($server -eq $null) {
        return Get-SPServiceInstance | ? {$_.GetType().ToString() -eq $service}
    } else {
        return Get-SPServiceInstance -Server $server | ? {$_.GetType().ToString() -eq $service}
    }
}

# Managed Account Functions
function global:GetOrCreateManagedAccount([string]$accountName, [string]$accountPassword) {
    $managedAccount = Get-SPManagedAccount | Where-Object {$_.UserName -eq $accountName}

    if ($managedAccount -eq $null) {
        $cred = GetCredential $accountName $accountPassword
        New-SPManagedAccount -Credential $cred | Out-Null
        $managedAccount = Get-SPManagedAccount | Where-Object {$_.UserName -eq $accountName}
    }
    
    return $managedAccount
}

function global:GetCredentials([string]$accountName, [string]$accountPassword) {
    if ($accountPassword -eq $null) {
        return $host.ui.PromptForCredential("SharePoint Managed Account", "Enter the password for this account", "$accountName", "NetBiosUserName")
    } else {
        return New-Object System.Management.Automation.PsCredential $accountName,$accountPassword
    }
}
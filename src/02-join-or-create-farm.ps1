# ---------------------------------------------------------------
# Join or Create Farm
# ---------------------------------------------------------------
# First run this script on your Central Admin Server.  The first
# run will create your SharePoint Farm.  Next run this script
# on each of your SharePoint Servers to join them to the farm.
# ---------------------------------------------------------------

# Load Configuration
&./config.ps1

# Load Global Functions
&./lib/common.ps1

info "Creating and configuring (or joining) farm"

Start-SPAssignment -Global | Out-Null

$isNewFarm = $false

try {
	info "Checking farm membership for $env:COMPUTERNAME in '$ConfigDB'..."
	$farm = Get-SPFarm | Where-Object {$_.Name -eq $ConfigDB} -ErrorAction SilentlyContinue
} catch {""}

if ($farm -eq $null) {
	try {
		info "Attempting to join farm on '$ConfigDB'..."
        $passPhrase = Convert-ToSecureString "$FarmPassPhrase" -AsPlaintext -Force
		$connectFarm = Connect-SPConfigurationDatabase -DatabaseName "$ConfigDB" -Passphrase $passPhrase -DatabaseServer "$DatabaseServer" -ErrorAction SilentlyContinue
		if (-not $?) {
			
            info "No existing farm found.  Creating new farm."
            sleep 5
            &./lib/create-farm.ps1
            
            $isNewFarm = true
		} else {
			$farmMessage = "Done joining farm."
		}
	
        info "Creating Version registry value (workaround for bug in PS-based install)"
    	info "Getting version number... "
    	$build = "$($(Get-SPFarm).BuildVersion.Major).0.0.$($(Get-SPFarm).BuildVersion.Build)"
    	info "$build"
    	New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Shared Tools\Web Server Extensions\14.0\' -Name Version -Value $build -ErrorAction SilentlyContinue | Out-Null
	} catch {
		Write-Output $_
		Pause
		break
	}
} else {
	$farmMessage = "$env:COMPUTERNAME is already joined to farm on '$ConfigDB'."
}
into $farmMessage

if($isNewFarm) {
    &./lib/config-farm.ps1
}

Stop-SPAssignment -Global | Out-Null
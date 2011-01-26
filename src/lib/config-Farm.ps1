# ---------------------------------------------------------------
# Configure the Farm
# ---------------------------------------------------------------
# This script will set up the first-time configuration of the
# farm.  It will provision central administration and start
# basic services.
# ---------------------------------------------------------------

function CreateCentralAdmin($port) {
	try {
		## Create Central Admin
		info "Creating Central Admin site..."
		$newCentralAdmin = New-SPCentralAdministration -Port $port -WindowsAuthProvider "NTLM" -ErrorVariable err
		if (-not $?) {throw}
        
		info "Waiting for Central Admin site to provision..."
		$centralAdmin = Get-SPWebApplication -IncludeCentralAdministration | ? {$_.Url -like "http://$($env:COMPUTERNAME):$port*"}
		
        while ($centralAdmin.Status -ne "Online") {
			write-progress
			sleep 1
			$centralAdmin = Get-SPWebApplication -IncludeCentralAdministration | ? {$_.Url -like "http://$($env:COMPUTERNAME):$port*"}
		}
		info "Done!"
        
	} catch	{
   		if ($err -like "*update conflict*") {
			warn "A concurrency error occured, trying again."
			CreateCentralAdmin $port
		} else {
			Write-Output $_
			Pause
			break
		}
	}
}

function ConfigureFarm {
	info "Configuring the SharePoint farm/server..."
	
    try {
        info " - Installing Help Collection..."
        Install-SPHelpCollection -All
            
		info "Securing Resources..."
		Initialize-SPResourceSecurity
		
        info "Installing Services..."
		Install-SPService
		
        info "Installing Features..."
		Install-SPFeature -AllExistingFeatures -Force
		
        info "Installing Application Content..."
		Install-SPApplicationContent
	} catch	{
	    if ($err -like "*update conflict*") {
			warn "A concurrency error occured, trying again."
			CreateCentralAdmin
		} else {
			Write-Output $_
			Pause
			break
		}
	}
    
	info "Completed initial farm/server config."
}



CreateCentralAdmin
ConfigureFarm
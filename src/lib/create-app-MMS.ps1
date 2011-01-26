# ---------------------------------------------------------------
# Create Managed Metadata Service Application
# ---------------------------------------------------------------
# This script will create managed metadata service applicationsc
# based on the definitions in config.ps1
# ---------------------------------------------------------------

function CreateMetadataServiceApp {
    $serviceName = $input.Get_Item("Name")
    $appPoolAccountName = $input.Get_Item("AppPoolAccount")
    $appPoolAccountPwd = $input.Get_Item("AppPoolAccountPwd")
    $appPoolName = $input.Get_Item("AppPoolName")
    $dbName = $input.Get_Item("DBName")
    $partitioned = $input.Get_Item("Partitioned")
    $adminAccount = $input.Get_Item("AdminAccount")
    $permissions = $input.Get_Item("Permissions")
    
    info "Creating Managed Metadata Service Application '$serviceName'"
    debug "  AppPool: '$appPoolName'"
    debug "  DBName:  '$dbName'"
    if ($partitioned) { debug "  Partitioned" }

    try {
        ## Get Managed Account
        $appPoolAccount = GetOrCreateManagedAccount $appPoolAccountName $appPoolAccountPassword
      	if ($appPoolAccount -eq $null) { throw "Managed Account $appPoolAccountName not found" }
	    
        
        ## Get or Create App Pool
		info "Getting Application Pool $appPoolName, creating if necessary..."
    	$appPool = Get-SPServiceApplicationPool $appPoolName -ea SilentlyContinue
        
        if ($appPool -eq $null) { 
            $appPool = New-SPServiceApplicationPool $appPoolName -account $appPoolAccount
            If (-not $?) { throw "Failed to create an application pool" }
      	}
        
        
 	    ## Create a Metadata Service Application
      	if((Get-SPServiceApplication -Name $serviceName) -eq $null) {      
			info "Creating Managed Metadata Service"
            
            ## Create Service App
   			info "Creating Metadata Service Application..."
            if ($partitioned) {
                $metaDataServiceApp  = New-SPMetadataServiceApplication -PartitionMode -Name $serviceName -ApplicationPool $appPool -DatabaseName $dbName -AdministratorAccount $adminAccount -FullAccessAccount $adminAccount
                if (-not $?) { throw "Failed to create Metadata Service Application" }
            } else {
                $metaDataServiceApp  = New-SPMetadataServiceApplication -Name $serviceName -ApplicationPool $appPool -DatabaseName $dbName -AdministratorAccount $adminAccount -FullAccessAccount $adminAccount
                if (-not $?) { throw "Failed to create Metadata Service Application" }
            }
            

            ## create proxy
			info "Creating Metadata Service Application Proxy..."
            $metaDataServiceAppProxy  = New-SPMetadataServiceApplicationProxy -Name "$serviceName Proxy" -ServiceApplication $MetaDataServiceApp -DefaultProxyGroup
            if (-not $?) { throw "- Failed to create Metadata Service Application Proxy" }
            
            
            ## Grant Rights to App
			info "Granting rights to Metadata Service Application..."
            
            ## Get ID of "Managed Metadata Service"
			$MetadataServiceAppToSecure = Get-SPServiceApplication -Name $serviceName
			$MetadataServiceAppIDToSecure = $MetadataServiceAppToSecure.Id
            
            ## Get security for app
            $MetadataServiceAppSecurity = Get-SPServiceApplicationSecurity $MetadataServiceAppIDToSecure
			
            ## Get the Claims Principals for each identity specified
            foreach ($a in $permissions.Keys) {
                $principal = New-SPClaimsPrincipal -Identity $a -IdentityType WindowsSamAccountName
                Grant-SPObjectSecurity $MetadataServiceAppSecurity -Principal $principal -Rights $permissions.Get_Item($a)
            }
            
			## Apply the changes to the Metadata Service application
			Set-SPServiceApplicationSecurity $MetadataServiceAppIDToSecure -objectSecurity $MetadataServiceAppSecurity
            
			info "Done creating Managed Metadata Service."
            
      	} else { info "Managed Metadata Service already exists."}
	} catch {
		Write-Output $_ 
	}
}

foreach ($def in $ManagedMetadataApplicationDefinitions) {
    CreateMetadataServiceApp $def
}
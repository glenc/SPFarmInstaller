# ---------------------------------------------------------------
# Basic Configuration
# ---------------------------------------------------------------
$global:CentralAdminPort           = 65001
$global:FarmPassPhrase             = "Share!Point"

$global:DatabaseServer             = "SQLDEV2008"
$global:ConfigDB                   = "SP_Config"
$global:CentralAdminContentDB      = "SP_AdminContent"

$global:FarmSvcAccount             = ""
$global:FarmSvcPwd                 = ""
$global:AdminAccount               = ""
$global:AdminPwd                   = ""


# ---------------------------------------------------------------
# Service Applications
# ---------------------------------------------------------------

# ---------------------------------------------------------------
# Managed Metadata Applications
# ---------------------------------------------------------------

# MMS Definitions
$ManagedMetadataApplication1 = @{
    "Name"              = "Managed Metadata";
    "DBName"            = "MMS_DB";
    "AppPoolName"       = "MMS_AppPool";
    "AppPoolAccount"    = "AppPoolAcct";
    "AppPoolAccountPwd" = "test";
    "Partitioned"       = $false;
    "AdminAccount"      = "";
    "Permissions"       = @{
                            "MMS_AppPool" = "Full Access to Term Store"; 
                            "asdf"        = "Full Access to Term Store" 
                           }
}

# All MMS Definitions
$global:ManagedMetadataApplicationDefinitions = $ManagedMetadataApplication1


# ---------------------------------------------------------------
# Farm Topology
# ---------------------------------------------------------------
$global:CentralAdminServer          = "SP2010-FARM-01"
$global:WebFrontEndServers          = "SP2010-FARM-01", "SP2010-FARM-02"
$global:ManagedMetadataAppServers   = "SP2010-FARM-02"
$global:SearchQueryServers          = "SP2010-FARM-01", "SP2010-FARM-02"
$global:SearchIndexServers          = "SP2010-FARM-02"
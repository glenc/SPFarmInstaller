# ---------------------------------------------------------------
# Security Functions
# ---------------------------------------------------------------

function GetSecureString([string]$str) {
    return ConvertTo-SecureString "$str" -AsPlaintext -Force
}

function GetCredential([string]$accountName, $config) {
    $account = $config.ManagedAccounts.Account | Where-Object {$_.name -eq $accountName}

    if ($account.username -eq $null -or $account.username -eq "" -or $account.password -eq $null -or $account.password -eq "") {
        return $host.ui.PromptForCredential("SharePoint Managed Account ($accountName)", "Enter the password for this account", $account.username, "NetBiosUserName")
    } else {
        $pwd = GetSecureString $account.password
        return New-Object System.Management.Automation.PsCredential $account.username,$pwd
    }
}

function GetOrCreateManagedAccount([string]$accountName, $config) {
    $username = GetManagedAccountUsername $accountName $config
    $managedAccount = Get-SPManagedAccount | Where-Object {$_.UserName -eq $username}

    if ($managedAccount -eq $null) {
        $cred = GetCredential $accountName $config
        New-SPManagedAccount -Credential $cred | Out-Null
        $managedAccount = Get-SPManagedAccount | Where-Object {$_.UserName -eq $username}
    }
    
    return $managedAccount
}

function GetManagedAccountUsername([string]$accountName, $config) {
    $act = $config.ManagedAccounts.Account | Where-Object {$_.name -eq $accountName}
    if ($act -eq $null) {
        return $accountName
    } else {
        return $act.username
    }
}
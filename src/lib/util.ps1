# ---------------------------------------------------------------
# Utility Functions
# ---------------------------------------------------------------

function LoadSharePointPowershell {
    if ((Get-PsSnapin |?{$_.Name -eq "Microsoft.SharePoint.PowerShell"})-eq $null) {
        Add-PsSnapin Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue | Out-Null
    }
}

function Pause {
    #From http://www.microsoft.com/technet/scriptcenter/resources/pstips/jan08/pstip0118.mspx
    Write-Host "Press any key to exit..."
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function info {
    Write-Host -ForegroundColor White $args
}

function debug {
    Write-Host -ForegroundColor Gray $args
}

function error {
    Write-Host -ForegroundColor Red $args
}

function warn([string]$msg) {
    Write-Warning $msg
}

function show-progress {
    Write-Host -ForegroundColor Blue "." -NoNewLine
}


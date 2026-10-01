[CmdletBinding()]
param(
    [ValidateSet('Tasks.Read', 'Tasks.ReadWrite')]
    [string[]] $Scopes = @('Tasks.ReadWrite'),

    [switch] $UseDeviceCode,

    [string] $AccountId,

    [ValidateRange(60, 900)]
    [int] $AuthTimeoutSeconds = 900,

    [string] $AuthDirectory = $(if ($env:MS_TODO_AUTH_DIR) { $env:MS_TODO_AUTH_DIR } else { Join-Path $HOME '.config\ms-todo' }),

    [ValidateSet('CurrentUser', 'Process')]
    [string] $ContextScope = 'CurrentUser',

    [switch] $ForceLogin,

    [switch] $InitializeOnly
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Get-MsTodoAuthenticationType {
    param(
        [Parameter(Mandatory)]
        [string] $ModuleBase
    )

    $dependencies = @(
        (Join-Path $ModuleBase 'Dependencies\Core'),
        (Join-Path $ModuleBase 'Dependencies\Desktop')
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $dependencies) {
        throw "Microsoft Graph authentication dependencies were not found under '$ModuleBase'."
    }
    [Reflection.Assembly]::LoadFrom((Join-Path $dependencies 'Microsoft.Identity.Client.dll')) | Out-Null
    [Reflection.Assembly]::LoadFrom((Join-Path $dependencies 'Microsoft.Identity.Client.Extensions.Msal.dll')) | Out-Null
    [Microsoft.Identity.Client.PublicClientApplicationBuilder]
}

function Initialize-MsTodoAuthDirectory {
    param(
        [Parameter(Mandatory)]
        [string] $Directory
    )

    $resolvedDirectory = [IO.Path]::GetFullPath($Directory)
    New-Item -ItemType Directory -Path $resolvedDirectory -Force | Out-Null

    $legacyDirectory = Join-Path $env:LOCALAPPDATA '.IdentityService'
    $legacyCandidates = @(
        (Join-Path $legacyDirectory 'mg.msal.cache.nocae'),
        (Join-Path $legacyDirectory 'mg.msal.cache')
    )
    $targetCache = Join-Path $resolvedDirectory 'msal.cache'
    if (-not (Test-Path -LiteralPath $targetCache)) {
        $legacyCache = $legacyCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if ($legacyCache) {
            [IO.File]::WriteAllBytes($targetCache, [IO.File]::ReadAllBytes($legacyCache))
        }
    }

    $resolvedDirectory
}

foreach ($moduleName in 'Microsoft.Graph.Authentication', 'Microsoft.Graph.Users') {
    if (-not (Get-Module -ListAvailable -Name $moduleName)) {
        throw "Required module '$moduleName' is not installed."
    }
    Import-Module $moduleName
}

$moduleBase = (Get-Module Microsoft.Graph.Authentication | Select-Object -First 1).ModuleBase
$authenticationType = Get-MsTodoAuthenticationType -ModuleBase $moduleBase
$clientIdField = [Microsoft.Graph.PowerShell.Authentication.AuthContext].GetField('PowerShellClientId', [Reflection.BindingFlags] 'NonPublic,Static')
if (-not $clientIdField) {
    throw 'Microsoft Graph PowerShell public client ID was not found.'
}
$clientId = [string] $clientIdField.GetValue($null)
$cacheDirectory = $null
if ($ContextScope -eq 'CurrentUser') {
    $cacheDirectory = Initialize-MsTodoAuthDirectory -Directory $AuthDirectory
}

if ($InitializeOnly) {
    [pscustomobject]@{
        AuthDirectory = $cacheDirectory
        CacheFiles    = @(if ($cacheDirectory) { Get-ChildItem -LiteralPath $cacheDirectory -Filter 'msal.cache*' -Force | Select-Object -ExpandProperty Name })
        ContextScope  = $ContextScope
    }
    return
}

if ($ForceLogin -and $cacheDirectory) {
    $storage = [Microsoft.Identity.Client.Extensions.Msal.StorageCreationPropertiesBuilder]::new('msal.cache', $cacheDirectory).Build()
    $cacheHelper = [Microsoft.Identity.Client.Extensions.Msal.MsalCacheHelper]::CreateAsync($storage, $null).GetAwaiter().GetResult()
    $cacheHelper.Clear()
}
if ($ForceLogin) {
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
}

$application = $authenticationType::Create($clientId).WithAuthority('https://login.microsoftonline.com/common').Build()
$cacheHelper = $null
if ($cacheDirectory) {
    $storage = [Microsoft.Identity.Client.Extensions.Msal.StorageCreationPropertiesBuilder]::new('msal.cache', $cacheDirectory).Build()
    $cacheHelper = [Microsoft.Identity.Client.Extensions.Msal.MsalCacheHelper]::CreateAsync($storage, $null).GetAwaiter().GetResult()
    $cacheHelper.VerifyPersistence()
    $cacheHelper.RegisterCache($application.UserTokenCache)
}

try {
    $accounts = @($application.GetAccountsAsync().GetAwaiter().GetResult())
    $account = $null
    if ($AccountId) {
        $account = $accounts | Where-Object { $_.HomeAccountId.Identifier -eq $AccountId } | Select-Object -First 1
        if (-not $account) {
            throw "No cached Microsoft account matched HomeAccountId '$AccountId'."
        }
    }
    elseif ($accounts.Count -eq 1) {
        $account = $accounts[0]
    }
    elseif ($accounts.Count -gt 1) {
        throw 'More than one Microsoft account is cached. Pass -AccountId with the selected HomeAccountId.'
    }

    $authenticationResult = $null
    $authenticationMethod = 'SilentCache'
    if (-not $ForceLogin -and $account) {
        $silentScopes = @()
        $silentScopes += ,([string[]] $Scopes)
        if ($Scopes.Count -eq 1 -and $Scopes[0] -eq 'Tasks.Read') {
            $silentScopes += ,([string[]] @('Tasks.ReadWrite'))
        }
        foreach ($candidateScopes in $silentScopes) {
            try {
                $authenticationResult = $application.AcquireTokenSilent($candidateScopes, $account).ExecuteAsync().GetAwaiter().GetResult()
                break
            }
            catch [Microsoft.Identity.Client.MsalUiRequiredException] {
            }
        }
    }

    if (-not $authenticationResult) {
        if (-not $UseDeviceCode) {
            throw 'MS_TODO_AUTH_REQUIRED: no reusable authorization is available. Run Connect-MsTodo.ps1 -UseDeviceCode once.'
        }
        # MSAL invokes this callback on a thread-pool thread with no PowerShell
        # runspace, so a scriptblock delegate would throw. Use compiled code.
        $msalDllPath = (Get-ChildItem -LiteralPath $moduleBase -Recurse -Filter 'Microsoft.Identity.Client.dll' |
            Select-Object -First 1).FullName
        $callbackReferences = @(
            $msalDllPath
            [System.Object].Assembly.Location
            [System.Threading.Tasks.Task].Assembly.Location
            [System.Console].Assembly.Location
        )
        Add-Type -TypeDefinition @'
            public static class MsTodoDeviceCodeCallback
            {
                public static System.Threading.Tasks.Task Print(Microsoft.Identity.Client.DeviceCodeResult result)
                {
                    System.Console.Error.WriteLine(result.Message);
                    return System.Threading.Tasks.Task.CompletedTask;
                }
            }
'@ -ReferencedAssemblies $callbackReferences
        $deviceCodeCallback = [System.Delegate]::CreateDelegate(
            [Func[Microsoft.Identity.Client.DeviceCodeResult, System.Threading.Tasks.Task]],
            [MsTodoDeviceCodeCallback].GetMethod('Print'))
        $cancellation = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds($AuthTimeoutSeconds))
        try {
            $authenticationMethod = 'DeviceCode'
            $authenticationResult = $application.AcquireTokenWithDeviceCode([string[]] $Scopes, $deviceCodeCallback).ExecuteAsync($cancellation.Token).GetAwaiter().GetResult()
        }
        finally {
            $cancellation.Dispose()
        }
    }
}
finally {
    if ($cacheHelper) {
        $cacheHelper.UnregisterCache($application.UserTokenCache)
    }
}

$accessToken = ConvertTo-SecureString $authenticationResult.AccessToken -AsPlainText -Force
Connect-MgGraph -AccessToken $accessToken -NoWelcome

$context = Get-MgContext
if (-not $context) {
    throw 'Microsoft Graph authentication did not produce a context.'
}

$availableScopes = @($authenticationResult.Scopes)
$missingScopes = @($Scopes | Where-Object {
    $_ -notin $availableScopes -and
    -not ($_ -eq 'Tasks.Read' -and 'Tasks.ReadWrite' -in $availableScopes)
})
if ($missingScopes.Count -gt 0) {
    throw "Authenticated context is missing delegated scope(s): $($missingScopes -join ', ')."
}

[pscustomobject]@{
    Account  = $authenticationResult.Account.Username
    AuthType = "Msal$authenticationMethod"
    TenantId = $authenticationResult.TenantId
    ClientId = $clientId
    Scopes   = @($authenticationResult.Scopes)
}

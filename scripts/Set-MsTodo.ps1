[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Create', 'Update', 'Complete', 'Delete')]
    [string] $Action,

    [Parameter(Mandatory)]
    [string] $ListName,

    [string] $TaskId,

    [string] $Title,

    [ValidateSet('low', 'normal', 'high')]
    [string] $Importance,

    [ValidateSet('notStarted', 'inProgress', 'completed', 'waitingOnOthers', 'deferred')]
    [string] $Status,

    [datetime] $DueOn,

    [string] $TimeZone = 'China Standard Time',

    [switch] $UseDeviceCode,

    [string] $AccountId,

    [ValidateRange(60, 900)]
    [int] $AuthTimeoutSeconds = 900,

    [string] $AuthDirectory = $(if ($env:MS_TODO_AUTH_DIR) { $env:MS_TODO_AUTH_DIR } else { Join-Path $HOME '.config\ms-todo' }),

    [switch] $AsJson
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

& (Join-Path $scriptRoot 'Connect-MsTodo.ps1') `
    -Scopes 'Tasks.ReadWrite' `
    -ContextScope CurrentUser `
    -UseDeviceCode:$UseDeviceCode `
    -AccountId $AccountId `
    -AuthTimeoutSeconds $AuthTimeoutSeconds `
    -AuthDirectory $AuthDirectory | Out-Null

$lists = @(Get-MgUserTodoList -UserId me -All)
$selectedLists = @($lists | Where-Object { $_.DisplayName -eq $ListName })
if ($selectedLists.Count -eq 0) {
    throw "No Microsoft To Do list named '$ListName' was found."
}
if ($selectedLists.Count -gt 1) {
    throw "More than one Microsoft To Do list is named '$ListName'; use a unique list name."
}
$todoList = $selectedLists[0]

if ($Action -eq 'Create') {
    if ([string]::IsNullOrWhiteSpace($Title)) {
        throw '-Title is required for Create.'
    }
}
elseif ([string]::IsNullOrWhiteSpace($TaskId)) {
    throw "-TaskId is required for $Action. Query the task first to resolve its exact ID."
}

$body = @{}
if ($PSBoundParameters.ContainsKey('Title')) {
    $body.title = $Title
}
if ($PSBoundParameters.ContainsKey('Importance')) {
    $body.importance = $Importance
}
if ($PSBoundParameters.ContainsKey('Status')) {
    $body.status = $Status
}
if ($PSBoundParameters.ContainsKey('DueOn')) {
    $body.dueDateTime = @{
        dateTime = $DueOn.ToString('yyyy-MM-ddTHH:mm:ss')
        timeZone = $TimeZone
    }
}

$result = $null
switch ($Action) {
    'Create' {
        if ($body.Count -eq 0) {
            throw 'Create has no task fields.'
        }
        if ($PSCmdlet.ShouldProcess("list '$($todoList.DisplayName)'", "Create task '$Title'")) {
            $result = New-MgUserTodoListTask -UserId me -TodoTaskListId $todoList.Id -BodyParameter $body
        }
    }
    'Update' {
        if ($body.Count -eq 0) {
            throw 'Update requires at least one of -Title, -Importance, -Status, or -DueOn.'
        }
        if ($PSCmdlet.ShouldProcess("task '$TaskId' in list '$($todoList.DisplayName)'", "Update fields: $($body.Keys -join ', ')")) {
            $result = Update-MgUserTodoListTask -UserId me -TodoTaskListId $todoList.Id -TodoTaskId $TaskId -BodyParameter $body
        }
    }
    'Complete' {
        if ($PSCmdlet.ShouldProcess("task '$TaskId' in list '$($todoList.DisplayName)'", 'Set status to completed')) {
            $result = Update-MgUserTodoListTask -UserId me -TodoTaskListId $todoList.Id -TodoTaskId $TaskId -BodyParameter @{ status = 'completed' }
        }
    }
    'Delete' {
        if ($PSCmdlet.ShouldProcess("task '$TaskId' in list '$($todoList.DisplayName)'", 'Delete task')) {
            $result = Remove-MgUserTodoListTask -UserId me -TodoTaskListId $todoList.Id -TodoTaskId $TaskId -Confirm:$false
        }
    }
}

# Emit structured JSON on request so callers on the other side of a process
# boundary (Windows PowerShell 5.1, agent harnesses) get IDs and dates intact
# instead of formatted display text. Delete intentionally returns nothing.
if ($null -ne $result) {
    if ($AsJson) {
        $result | ConvertTo-Json -Depth 8
    }
    else {
        $result
    }
}

[CmdletBinding(DefaultParameterSetName = 'Tasks')]
param(
    [Parameter(ParameterSetName = 'Lists')]
    [switch] $List,

    [Parameter(ParameterSetName = 'Tasks')]
    [string] $ListName,

    [Parameter(ParameterSetName = 'Tasks')]
    [switch] $Important,

    [Parameter(ParameterSetName = 'Tasks')]
    [datetime] $DueOn,

    [Parameter(ParameterSetName = 'Tasks')]
    [ValidateSet('notStarted', 'inProgress', 'completed', 'waitingOnOthers', 'deferred')]
    [string] $Status,

    [Parameter(ParameterSetName = 'Tasks')]
    [string] $Title,

    [Parameter(ParameterSetName = 'Tasks')]
    [switch] $IncludeCompleted,

    [Parameter(ParameterSetName = 'Tasks')]
    [string] $DisplayTimeZone = (Get-TimeZone).Id,

    [switch] $UseDeviceCode,

    [string] $AccountId,

    [ValidateRange(60, 900)]
    [int] $AuthTimeoutSeconds = 900,

    [string] $AuthDirectory = $(if ($env:MS_TODO_AUTH_DIR) { $env:MS_TODO_AUTH_DIR } else { Join-Path $HOME '.config\ms-todo' }),

    [switch] $AsJson
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function ConvertTo-MsTodoDisplayTime {
    param(
        [Parameter(Mandatory)]
        [object] $Value,

        [Parameter(Mandatory)]
        [string] $TargetTimeZone
    )

    if (-not $Value.DateTime -or -not $Value.TimeZone) {
        return $null
    }

    $sourceZone = [TimeZoneInfo]::FindSystemTimeZoneById($Value.TimeZone)
    $targetZone = [TimeZoneInfo]::FindSystemTimeZoneById($TargetTimeZone)
    $unspecified = [datetime]::SpecifyKind(
        [datetime]::Parse(
            $Value.DateTime,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AllowWhiteSpaces
        ),
        [DateTimeKind]::Unspecified
    )
    $utc = [TimeZoneInfo]::ConvertTimeToUtc($unspecified, $sourceZone)
    [TimeZoneInfo]::ConvertTimeFromUtc($utc, $targetZone)
}

& (Join-Path $scriptRoot 'Connect-MsTodo.ps1') `
    -Scopes 'Tasks.Read' `
    -ContextScope CurrentUser `
    -UseDeviceCode:$UseDeviceCode `
    -AccountId $AccountId `
    -AuthTimeoutSeconds $AuthTimeoutSeconds `
    -AuthDirectory $AuthDirectory | Out-Null

$lists = @(Get-MgUserTodoList -UserId me -All)

if ($PSCmdlet.ParameterSetName -eq 'Lists') {
    $result = @($lists | Select-Object Id, DisplayName, WellknownListName)
}
else {
    if ($ListName) {
        $selectedLists = @($lists | Where-Object { $_.DisplayName -eq $ListName })
        if ($selectedLists.Count -eq 0) {
            throw "No Microsoft To Do list named '$ListName' was found."
        }
        if ($selectedLists.Count -gt 1) {
            throw "More than one Microsoft To Do list is named '$ListName'; use a unique list name."
        }
    }
    else {
        $selectedLists = $lists
    }

    $tasks = foreach ($todoList in $selectedLists) {
        foreach ($task in @(Get-MgUserTodoTask -UserId me -TodoTaskListId $todoList.Id -All)) {
            $dueLocalDateTime = if ($task.DueDateTime.DateTime) {
                ConvertTo-MsTodoDisplayTime -Value $task.DueDateTime -TargetTimeZone $DisplayTimeZone
            }
            else {
                $null
            }
            [pscustomobject]@{
                ListId               = $todoList.Id
                ListName             = $todoList.DisplayName
                Id                   = $task.Id
                Title                = $task.Title
                Importance           = $task.Importance
                Status               = $task.Status
                DueDateTime          = $task.DueDateTime
                DueLocalDateTime     = $dueLocalDateTime
                DisplayTimeZone      = $DisplayTimeZone
                StartDateTime        = $task.StartDateTime
                ReminderDateTime     = $task.ReminderDateTime
                IsReminderOn         = $task.IsReminderOn
                CreatedDateTime      = $task.CreatedDateTime
                LastModifiedDateTime = $task.LastModifiedDateTime
            }
        }
    }

    if (-not $IncludeCompleted) {
        $tasks = @($tasks | Where-Object { $_.Status -ne 'completed' })
    }
    if ($Important) {
        $tasks = @($tasks | Where-Object { $_.Importance -eq 'high' })
    }
    if ($Status) {
        $tasks = @($tasks | Where-Object { $_.Status -eq $Status })
    }
    if ($Title) {
        # Escape wildcard metacharacters so callers can search literal titles
        # like "[skill-test]" without the pattern matching unrelated tasks.
        $escapedTitle = [System.Management.Automation.WildcardPattern]::Escape($Title)
        $tasks = @($tasks | Where-Object { $_.Title -like "*$escapedTitle*" })
    }
    if ($PSBoundParameters.ContainsKey('DueOn')) {
        $tasks = @($tasks | Where-Object {
            $_.DueLocalDateTime -and $_.DueLocalDateTime.Date -eq $DueOn.Date
        })
    }

    $result = @($tasks | Sort-Object ListName, DueDateTime, Title)
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 8
}
else {
    $result
}

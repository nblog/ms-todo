# ms-todo

An [agent skill](https://skills.sh/) for authenticating to Microsoft Graph and querying or managing [Microsoft To Do](https://to-do.office.com/) lists and tasks with reusable PowerShell scripts. Use it for listing, filtering, creating, updating, completing, or deleting To Do tasks.

## Install

```bash
npx skills add nblog/ms-todo
```

## How it works

The skill ships three scripts under `scripts/` instead of rebuilding authentication and Graph calls each time:

| Script | Purpose | Delegated scope |
| --- | --- | --- |
| `Connect-MsTodo.ps1` | Authenticate or refresh the cached session | `Tasks.ReadWrite` (default), pass `-Scopes Tasks.Read` for read-only |
| `Get-MsTodo.ps1` | Query lists and tasks (filter by list, importance, status, due date, title) | `Tasks.Read` only |
| `Set-MsTodo.ps1` | Create, update, complete, or delete a task | `Tasks.ReadWrite` |

They use the Microsoft Graph PowerShell public client — ordinary interactive use does not require a user-created Azure application or client secret — with a per-user MSAL cache under `~/.config/ms-todo/` protected by Microsoft.Identity.Client.Extensions.Msal.

## Requirements

- PowerShell 7+ (pwsh) recommended
- PowerShell modules `Microsoft.Graph.Authentication` and `Microsoft.Graph.Users`; if either is missing the scripts report it instead of installing implicitly:

  ```powershell
  Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Users -Scope CurrentUser
  ```

## Usage

### Authenticate

The first sign-in uses the device-code flow; afterwards runs reuse the silent cache:

```powershell
# First sign-in (read-only session)
scripts/Connect-MsTodo.ps1 -Scopes Tasks.Read -UseDeviceCode

# Later runs: silent cache, no prompts
scripts/Connect-MsTodo.ps1

# Cache-only diagnostics: create/inspect the cache directory without authenticating
scripts/Connect-MsTodo.ps1 -InitializeOnly
```

Useful switches: `-AccountId <HomeAccountId>` when more than one account is cached, `-ForceLogin` to clear the cache and sign in again, `-AuthTimeoutSeconds` (60–900) for the device-code window, and `-AuthDirectory` / `MS_TODO_AUTH_DIR` to override the cache location.

### Query

```powershell
# All To Do lists
scripts/Get-MsTodo.ps1 -List

# Open tasks across all lists (completed tasks excluded by default)
scripts/Get-MsTodo.ps1

# High-importance tasks due 2026-10-08 in the "Work" list
scripts/Get-MsTodo.ps1 -ListName 'Work' -Important -DueOn 2026-10-08

# Literal title search (wildcard metacharacters are escaped)
scripts/Get-MsTodo.ps1 -Title '[release]'
```

Microsoft To Do's **Important** view is usually not a separate `todoTaskList`; `-Important` matches tasks whose `importance` is `high`. List names are resolved to IDs and ambiguous names fail rather than guess.

### Mutate

```powershell
# Preview any mutation before running it for real
scripts/Set-MsTodo.ps1 -Action Complete -ListName 'Work' -TaskId <task-id> -WhatIf

# Create
scripts/Set-MsTodo.ps1 -Action Create -ListName 'Work' -Title 'Ship release' -DueOn 2026-10-08 -Importance high

# Update
scripts/Set-MsTodo.ps1 -Action Update -ListName 'Work' -TaskId <task-id> -Status inProgress

# Complete / Delete
scripts/Set-MsTodo.ps1 -Action Complete -ListName 'Work' -TaskId <task-id>
scripts/Set-MsTodo.ps1 -Action Delete   -ListName 'Work' -TaskId <task-id>
```

`Set-MsTodo.ps1` supports `-WhatIf`/`-Confirm` (`ConfirmImpact = 'High'`). Due dates accept `-DueOn <datetime>` plus `-TimeZone` (a Windows time-zone name, default `China Standard Time`); Graph's `dateTime` + `timeZone` pair is preserved as-is.

### Automation and cross-process callers

Graph task objects do not survive a process boundary as live objects: a nested `pwsh -File` call returns formatted text, which loses task IDs and date-time pairs. Callers on the other side of a process boundary (Windows PowerShell 5.1 driving pwsh 7, or an agent harness) should pass `-AsJson` and parse the output:

```powershell
$tasks = pwsh -File scripts/Get-MsTodo.ps1 -AsJson | ConvertFrom-Json
pwsh -File scripts/Set-MsTodo.ps1 -Action Complete -ListName 'Work' -TaskId $tasks[0].Id -AsJson
```

Callers inside the same PowerShell process should invoke the scripts with `& $script @splat` to keep live objects, which also amortizes the per-call module import and MSAL cache unlock.

## Safety boundaries

- Do not infer permission for a mutation from the skill being invoked or from its default scope. Query freely when requested; before a live create, update, complete, or delete, show the resolved target and intended change and obtain authorization for that exact mutation.
- Never broaden the requested scope beyond `Tasks.ReadWrite`.
- Keep tokens out of output, files, command history, and logs; report `Get-MgContext` metadata only.
- The MSAL cache is user-bound and encrypted at rest on Windows. Never copy it to logs, chat, another Windows account, or another machine.

## References

- [Graph contract notes](references/graph-contract.md) — permissions, endpoints, cmdlet names, smart views, and `dateTimeTimeZone` semantics
- [Microsoft Graph To Do API](https://learn.microsoft.com/graph/api/resources/todo-overview)
- [Microsoft Graph PowerShell authentication](https://learn.microsoft.com/powershell/microsoftgraph/authentication-commands)

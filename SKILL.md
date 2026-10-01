---
name: ms-todo
description: Authenticate to Microsoft Graph and query or manage Microsoft To Do lists and tasks with reusable PowerShell scripts. Use for listing, filtering, creating, updating, completing, or deleting To Do tasks.
---

# Microsoft To Do

Use the scripts in `scripts/` instead of rebuilding authentication and Graph calls. They use the Microsoft Graph PowerShell public client and a per-user MSAL cache under `~/.config/ms-todo/`; The cache is protected by Microsoft.Identity.Client.Extensions.Msal and must not be copied to logs, chat, or another machine.

## Choose the operation

- Authenticate or refresh the cached session: run `scripts/Connect-MsTodo.ps1`. Its default delegated scope is `Tasks.ReadWrite`, as requested by the skill owner. Pass `-Scopes Tasks.Read` for a read-only session. Normal runs are silent-cache only; use `-UseDeviceCode` explicitly for the first sign-in or after the cache is invalidated.
- Query lists and tasks: run `scripts/Get-MsTodo.ps1`. It requests only `Tasks.Read` by default, even though the authentication helper defaults to read/write.
- Create, update, complete, or delete a task: run `scripts/Set-MsTodo.ps1`. It requests `Tasks.ReadWrite`; use an explicit action and target. Preview mutations with `-WhatIf` when practical.

## Output and process boundaries

`Get-MsTodo.ps1` and `Set-MsTodo.ps1` both support `-AsJson`. Graph task objects do not survive a process boundary as objects: a nested `pwsh -File` call returns formatted text, which loses task IDs and date-time pairs. Cross-process callers (Windows PowerShell 5.1 driving pwsh 7, or an agent harness) should pass `-AsJson` and parse the JSON, resolving task IDs from the parsed output instead of transcribing them. Callers inside the same PowerShell process should invoke the scripts with `& $script @splat` to keep live objects, which also amortizes the per-call module import and MSAL cache unlock.

Do not infer permission for a mutation from the skill being invoked or from its default scope. Query freely when requested. Before a live create, update, complete, or delete, show the resolved target and intended change and obtain the user's authorization when the request has not already authorized that exact mutation. Never broaden the requested scope beyond `Tasks.ReadWrite`.

## Run safely

Prefer pwsh 7+. Import `Microsoft.Graph.Authentication` and `Microsoft.Graph.Users`; if either module is unavailable, report the missing module instead of installing it implicitly.

Keep tokens out of output, files, command history, and logs. Report `Get-MgContext` metadata only: account, authentication type, tenant, client ID, and scopes.

Microsoft To Do's **Important** view is usually not a separate `todoTaskList`. Treat it as tasks whose `importance` is `high`. Resolve list names to IDs before task calls, fail on ambiguous names, and preserve Graph's `dateTime` plus `timeZone` pair when reading or writing dates.

Use `-ContextScope CurrentUser` for sign-in so later runs can reuse and refresh the token cache. `Connect-MsTodo.ps1` stores the encrypted MSAL cache and never falls back to plaintext. Device-code login is the explicit bootstrap path when WAM or the interactive browser is unavailable. A cached refresh token can still require reauthentication after revocation, password/policy changes, cache removal, or Microsoft identity policy decisions.

The first-time flow is `scripts/Connect-MsTodo.ps1 -Scopes Tasks.Read -UseDeviceCode`; after it succeeds, omit `-UseDeviceCode` for queries and mutations. Use `-InitializeOnly` to create or inspect the cache directory without authenticating. If more than one account is cached, pass the selected account's `HomeAccountId` with `-AccountId`.

Set `MS_TODO_AUTH_DIR` or pass `-AuthDirectory` only when the default per-user directory must be overridden. The cache is user-bound on Windows; do not copy it to another Windows account or machine as a portable credential.

If PowerShell reports `SEC_E_NO_CREDENTIALS` or `The SSL connection could not be established`, classify it as a local Schannel/.NET transport failure after confirming the same account and scope work elsewhere. Do not respond by requesting broader Graph permissions.

Read [references/graph-contract.md](references/graph-contract.md) when interpreting list semantics, permissions, dates, statuses, or raw Graph responses.

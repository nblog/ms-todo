# Microsoft Graph To Do contract

## Permissions

- `Tasks.Read` reads the signed-in user's To Do lists and tasks.
- `Tasks.ReadWrite` reads and mutates the signed-in user's To Do lists and tasks.
- These are delegated permissions and work with personal Microsoft accounts.
- The Microsoft Graph PowerShell SDK uses Microsoft's public client by default, so ordinary interactive use does not require a user-created Azure application or client secret.

## Authentication cache

- The skill stores the per-user MSAL cache under `~/.config/ms-todo/` using Microsoft.Identity.Client.Extensions.Msal.
- The cache is encrypted at rest on Windows and is intentionally not emitted by the scripts.
- Query and mutation scripts attempt silent cache reuse only. Bootstrap or recovery requires the explicit `-UseDeviceCode` switch.

Use the least scope needed by each script. A previously granted `Tasks.ReadWrite` consent may be reused by the identity platform; a query still must not perform mutations.

## Resources

- Lists: `GET /me/todo/lists`
- Tasks: `GET /me/todo/lists/{list-id}/tasks`
- Create: `POST /me/todo/lists/{list-id}/tasks`
- Update: `PATCH /me/todo/lists/{list-id}/tasks/{task-id}`
- Delete: `DELETE /me/todo/lists/{list-id}/tasks/{task-id}`

Graph PowerShell cmdlets in `Microsoft.Graph.Users`:

- `Get-MgUserTodoList`
- `Get-MgUserTodoTask`
- `New-MgUserTodoListTask`
- `Update-MgUserTodoListTask`
- `Remove-MgUserTodoListTask`

`Get-MgUserTodoListTask` is not the current read cmdlet name; use `Get-MgUserTodoTask`.

## Important and dates

Microsoft To Do's Important smart view is represented by `todoTask.importance = high`; it does not have to appear as a list from `/me/todo/lists`.

Graph date fields use a `dateTimeTimeZone` object:

```json
{
  "dateTime": "2026-10-08T00:00:00",
  "timeZone": "China Standard Time"
}
```

Preserve both fields. Avoid appending `Z` unless the supplied value is actually UTC. When comparing a date for the user's locale, interpret the accompanying Windows time-zone name before reducing the value to a calendar date.

## Sources

- https://learn.microsoft.com/graph/api/resources/todo-overview
- https://learn.microsoft.com/graph/api/todo-list-lists
- https://learn.microsoft.com/graph/api/todotasklist-list-tasks
- https://learn.microsoft.com/graph/permissions-reference#tasksread
- https://learn.microsoft.com/graph/permissions-reference#tasksreadwrite
- https://learn.microsoft.com/powershell/microsoftgraph/authentication-commands
- https://learn.microsoft.com/powershell/module/microsoft.graph.authentication/connect-mggraph

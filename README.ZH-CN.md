# Microsoft To Do Skill

用于认证 Microsoft Graph,并通过可复用的 PowerShell 脚本查询或管理 [Microsoft To Do](https://to-do.office.com/) 的列表与任务。适用于列出、过滤、创建、更新、完成或删除 To Do 任务。

## 安装

```bash
npx skills add nblog/ms-todo
```

## 工作方式

该技能在 `scripts/` 下提供三个脚本,避免每次都重新构建认证与 Graph 调用:

| 脚本 | 用途 | 委派权限(delegated scope) |
| --- | --- | --- |
| `Connect-MsTodo.ps1` | 认证或刷新缓存会话 | 默认 `Tasks.ReadWrite`,传 `-Scopes Tasks.Read` 可只读 |
| `Get-MsTodo.ps1` | 查询列表与任务(按列表、重要性、状态、截止日期、标题过滤) | 仅使用 `Tasks.Read` |
| `Set-MsTodo.ps1` | 创建、更新、完成或删除任务 | `Tasks.ReadWrite` |

脚本使用 Microsoft Graph PowerShell 公共客户端 —— 普通交互使用无需自建 Azure 应用或客户端密钥 —— 并将每用户 MSAL 缓存保存在 `~/.config/ms-todo/` 下,由 Microsoft.Identity.Client.Extensions.Msal 保护。

## 环境要求

- 推荐使用 PowerShell 7+(pwsh)
- PowerShell 模块 `Microsoft.Graph.Authentication` 与 `Microsoft.Graph.Users`;缺失时脚本会明确报告而不是隐式安装:

  ```powershell
  Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Users -Scope CurrentUser
  ```

## 用法

### 认证

首次登录使用设备码(device-code)流程;之后的运行复用静默缓存:

```powershell
# 首次登录(只读会话)
scripts/Connect-MsTodo.ps1 -Scopes Tasks.Read -UseDeviceCode

# 后续运行:静默缓存,无交互提示
scripts/Connect-MsTodo.ps1

# 仅诊断缓存:创建/检查缓存目录,不做认证
scripts/Connect-MsTodo.ps1 -InitializeOnly
```

常用参数:缓存了多个账户时用 `-AccountId <HomeAccountId>` 选择;`-ForceLogin` 清缓存重新登录;`-AuthTimeoutSeconds`(60–900)控制设备码等待窗口;`-AuthDirectory` / `MS_TODO_AUTH_DIR` 覆盖缓存目录。

### 查询

```powershell
# 所有 To Do 列表
scripts/Get-MsTodo.ps1 -List

# 跨列表查询未完成任务(默认排除已完成)
scripts/Get-MsTodo.ps1

# "Work" 列表中 2026-10-08 到期的高重要性任务
scripts/Get-MsTodo.ps1 -ListName 'Work' -Important -DueOn 2026-10-08

# 按标题字面搜索(通配符元字符会被转义)
scripts/Get-MsTodo.ps1 -Title '[release]'
```

Microsoft To Do 的**重要(Important)**视图通常不是一个独立的 `todoTaskList`;`-Important` 匹配的是 `importance` 为 `high` 的任务。列表名会先解析为 ID,名称存在歧义时直接报错而不是猜测。

### 变更

```powershell
# 真正执行前可先用 -WhatIf 预览任意变更
scripts/Set-MsTodo.ps1 -Action Complete -ListName 'Work' -TaskId <task-id> -WhatIf

# 创建
scripts/Set-MsTodo.ps1 -Action Create -ListName 'Work' -Title 'Ship release' -DueOn 2026-10-08 -Importance high

# 更新
scripts/Set-MsTodo.ps1 -Action Update -ListName 'Work' -TaskId <task-id> -Status inProgress

# 完成 / 删除
scripts/Set-MsTodo.ps1 -Action Complete -ListName 'Work' -TaskId <task-id>
scripts/Set-MsTodo.ps1 -Action Delete   -ListName 'Work' -TaskId <task-id>
```

`Set-MsTodo.ps1` 支持 `-WhatIf`/`-Confirm`(`ConfirmImpact = 'High'`)。截止日期用 `-DueOn <datetime>` 配合 `-TimeZone`(Windows 时区名,默认取本机时区,与 `Get-MsTodo.ps1` 的显示默认一致);Graph 的 `dateTime` + `timeZone` 键值对会原样保留。

### 自动化与跨进程调用

Graph 任务对象无法以活动对象形式跨进程存活:嵌套的 `pwsh -File` 调用返回的是格式化文本,会丢失任务 ID 与日期时间对。位于进程边界另一侧的调用方(用 Windows PowerShell 5.1 驱动 pwsh 7,或 agent harness)应传 `-AsJson` 并解析输出:

```powershell
$tasks = pwsh -File scripts/Get-MsTodo.ps1 -AsJson | ConvertFrom-Json
pwsh -File scripts/Set-MsTodo.ps1 -Action Complete -ListName 'Work' -TaskId $tasks[0].Id -AsJson
```

同一 PowerShell 进程内的调用方应使用 `& $script @splat` 方式调用以保留活动对象,这同时能摊薄每次调用的模块导入与 MSAL 缓存解锁开销。

## 参考资料

- [Graph 契约笔记](references/graph-contract.md) — 权限、端点、cmdlet 名称、智能视图与 `dateTimeTimeZone` 语义
- [Microsoft Graph To Do API](https://learn.microsoft.com/graph/api/resources/todo-overview)
- [Microsoft Graph PowerShell 认证](https://learn.microsoft.com/powershell/microsoftgraph/authentication-commands)

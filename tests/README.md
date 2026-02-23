# InitGit tests

Pester tests for CloneAndInit and Install-InitGit. Compatible with Pester 3 (Windows built-in) and Pester 5.

## Run tests

**If you get "not digitally signed" / execution policy errors**, use one of these:

### Option 1: Use the runner (recommended)

From the repo root:

```cmd
run-tests.bat
```

This runs PowerShell with `-ExecutionPolicy Bypass` so the test scripts load.

### Option 2: Invoke Pester with Bypass

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-Location 'P:\Resources\Scripts\InitGit'; Invoke-Pester -Path tests -PassThru"
```

### Option 3: Set execution policy for the current user (persistent)

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

Then you can run:

```powershell
Invoke-Pester -Path tests -PassThru
```

---

- **CloneAndInit.Tests.ps1** – `Get-RepoNameFromUrl` and URL parsing.
- **Install-InitGit.Tests.ps1** – Install script structure and install-into-temp execution.

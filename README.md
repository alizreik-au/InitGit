# InitGit

This repo contains the scripts used to install and run the InitGit Windows context menu tools.

## Install

From the repo root, run:

```cmd
Install InitGit.bat
```

That launches the installer and sets up:

- the files under `%LOCALAPPDATA%\InitGit`
- the Windows right-click context menu entries

## What To Use

- `Install InitGit.bat`
  The main entrypoint for users installing or updating InitGit.
- `src/`
  Source scripts copied into the installed InitGit folder.
- `install/`
  Installer implementation files.
- `tests/`
  Pester tests.
- `tools/`
  Legacy or maintenance helpers.
- `docs/`
  Supporting notes and documentation.

## Repo Layout

- The repo root is intentionally minimal so the install entrypoint is obvious.
- The installer copies the scripts from `src/` into `%LOCALAPPDATA%\InitGit`.
- The normal starting point for a user is `Install InitGit.bat`, not the individual script files.

# Windows Payload Scripts

This directory contains PowerShell scripts that can be executed on Windows instances via lacework-deploy. Each script uses the `ENV_CONTEXT` and `TAG` environment variables and logs output to `$env:TEMP\<TAG>.log`.

## Shared Utilities
- **common.ps1**: Shared functions and helpers (logging, locking, random sleep, payload decoding).

## Deployment Scripts
- **deploy_docker.ps1**: Install Docker (Docker CE/desktop) and start the service.
- **deploy_git.ps1**: Install Git.
- **deploy_pwsh7.ps1**: Install PowerShell 7.
- **rdp_user.ps1**: Create and configure an RDP-enabled Windows user.

## Orchestration
- **run_me.ps1**: Orchestrate execution of Windows payload scripts based on the `TAG`.
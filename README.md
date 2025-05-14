# lacework-deploy-payloads

This repository contains a collection of payload scripts for Linux and Windows instances, designed to work in conjunction with the [lacework-deploy](https://github.com/lacework-dev/lacework-deploy/) tool. These scripts can deploy software, simulate attack scenarios, generate traffic, and demonstrate telemetry collection capabilities.

When invoked via lacework-deploy, the following environment variables are provided:

- **ENV_CONTEXT**: A list of provisioned compute instances with their public/private IPs and DNS names (if Dynu DNS is enabled).
- **TAG**: The instance tag that triggers the script, typically matching the script’s base name.

Directory layout:

- **linux/**: Bash payload scripts for Linux instances.
- **windows/**: PowerShell payload scripts for Windows instances.

For detailed descriptions of the scripts in each directory, see:

- [linux/README.md](linux/README.md)
- [windows/README.md](windows/README.md)

## Contributing

Each script added to this repository is required to pass either shellcheck or invoke-scriptanalyzer for shell and powershell scripts respectively. Additionally each of the scripts should have an entry in README.md. To check scripts against the pipeline test use `make lint`.
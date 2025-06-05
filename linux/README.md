# Linux Payload Scripts

This directory contains Bash scripts that can be executed on Linux instances via lacework-deploy. Each script uses the `ENV_CONTEXT` and `TAG` environment variables to target instances and logs output to `/tmp/lacework_deploy_<TAG>.log`.

## Shared Utilities
- **common.sh**: Shared functions and helpers (logging, locking, package manager detection).

## Connection Scripts
- **connect-badip.sh**: Attempt connections to invalid/bad IP addresses.
- **connect-codecov.sh**: Simulate traffic to Codecov endpoints.
- **connect-nmap-port-scan.sh**: Perform port scans using `nmap`.
- **connect-oast-host.sh**: Trigger OAST (out-of-band application security testing) callbacks.
- **connect-reverse-shell.sh**: Establish a reverse shell back to a listener.
- **connect-ssh-shell-multistage.sh**: Multi-stage SSH shell via piped payloads.
- **connect-ssh-shell-multistage_scan.sh**: Multi-stage SSH shell with scanning.
- **connect-ssh-lateral-movement.sh**: Scan local system for private keys and the attempt to connect to hosts in the same subnet using the discovered keys.

## Deployment Scripts
- **deploy-aws-cli.sh**: Install and configure the AWS CLI.
- **deploy-aws-credentials.sh**: Provision AWS credentials from environment variables.
- **deploy-azure-cli.sh**: Install and configure the Azure CLI.
- **deploy-azure-credentials.sh**: Provision Azure credentials from environment variables.
- **deploy-gcp-cli.sh**: Install and configure the Google Cloud SDK (`gcloud`).
- **deploy-gcp-credentials.sh**: Provision GCP credentials from environment variables.
- **deploy-docker.sh**: Install Docker and start the daemon.
- **deploy-docker-log4j-app.sh**: Deploy a Docker container running a vulnerable Log4j application.
- **deploy-git.sh**: Install Git.
- **deploy-inspector-agent.sh**: Install the AWS Inspector agent.
- **deploy-kubectl-cli.sh**: Install the `kubectl` CLI for Kubernetes.
- **deploy-lacework-agent.sh**: Install the Lacework agent.
- **deploy-lacework-agent_setup_lacework_agent.sh**: Helper for Lacework agent setup.
- **deploy-lacework-cli.sh**: Install the Lacework CLI.
- **deploy-lacework-code-aware-agent.sh**: Install the Lacework Code Aware agent.
- **deploy-lacework-syscall-config.sh**: Configure Lacework syscall monitoring.
- **deploy-log4j-app.sh**: Deploy a standalone vulnerable Log4j application.
- **deploy-npm-app.sh**: Deploy a Node.js NPM-based application.
- **deploy-protonvpn-docker.sh**: Deploy a ProtonVPN client in Docker.
- **deploy-python3-twisted-app.sh**: Deploy a Python 3 Twisted-based application.
- **deploy-rds-app.sh**: Deploy a sample RDS-backed application.
- **deploy-ssh-keys_private.sh**: Inject private SSH keys into the instance.
- **deploy-ssh-keys_public.sh**: Inject public SSH keys into the instance.
- **deploy-ssh-user.sh**: Create and configure an SSH user.

## Action Scripts
- **drop-malware-eicar.sh**: Download and drop the EICAR test file to simulate malware.
- **exec-touch-file.sh**: Create (touch) a file to simulate artifact creation.

## Execution Scripts
- **execute-cpu-miner.sh**: Run a CPU-based cryptocurrency miner.
- **execute-docker-cpu-miner.sh**: Run a CPU miner inside a Docker container.
- **execute-docker-exploit-log4j.sh**: Exploit a Log4j vulnerability in Docker.
- **execute-docker-hydra.sh**: Run Hydra brute-forcing inside Docker.
- **execute-docker-nmap.sh**: Perform `nmap` scans inside Docker.
- **execute-exploit-authapp.sh**: Exploit a sample authentication application.
- **execute-exploit-npm-app.sh**: Exploit a deployed Node.js NPM application.
- **execute-generate-aws-cli-traffic.sh**: Generate simulated AWS CLI traffic.
- **execute-generate-azure-cli-traffic.sh**: Generate simulated Azure CLI traffic.
- **execute-generate-gcp-cli-traffic.sh**: Generate simulated GCP CLI traffic.
- **execute-generate-web-traffic.sh**: Generate simulated web traffic.

## Listener Scripts
- **listener-http-listener.sh**: Start an HTTP server to catch callbacks.
- **listener-port-forward.sh**: Forward local ports to remote hosts.

## RDP and Responder Scripts
- **rdp_brute.sh**: Perform RDP brute-force attacks.
- **responder-port-forward.sh**: Use Responder to forward SMB/NTLM traffic.
- **responder-reverse-shell.sh**: Reverse shell scenarios using Responder (multistage variants).

## Testing
- **run_me.sh**: Enumerate `ENV_CONTEXT` and load common functions.
- **test.sh**: Load common functions and run `touch /tmp/pwned.txt.
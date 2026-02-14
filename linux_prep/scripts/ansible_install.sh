#!/bin/bash

# Description: Install ansible
# Steps: Make ssh key, get ssh hostkeys, makes python virtual environment, installs ansible to the virtual environment.

REMOTE_USER=root

if [ $(whoami) != "ansible-control" ];
then
  echo "Please install run setup.sh first!"
  exit 1
fi

# Source - https://stackoverflow.com/a/29436423
# Posted by Tiago Lopo, modified by community. See post 'Timeline' for change history
# Retrieved 2026-02-04, License - CC BY-SA 3.0
function yes_or_no {
    while true; do
        read -p "$* [y/n]: " yn
        case $yn in
            [Yy]*) return 0  ;;  
            [Nn]*) return 1  ;;
        esac
    done
}

yes_or_no "Copy SSH key to remote hosts?"
COPY_BOOL=$?

DIRECTORY=~/repo
SSH_HOSTS=~/.ssh/known_hosts
set -euo pipefail

ssh-keygen -t ed25519

#https://stackoverflow.com/questions/427979/how-do-you-extract-ip-addresses-from-files-using-a-regex-in-a-linux-shell#427989
IP_ADDRESSES=$(grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' $DIRECTORY/inventory.ini | uniq)

touch $SSH_HOSTS 
chmod go-rwx $SSH_HOSTS

set +euo pipefail
for IP in $IP_ADDRESSES
do
  # Checking if host is already known
  ssh-keygen -F $IP >> /dev/null
  if [ "$?" -eq 0 ]
  then
    echo "Skipping ${IP}. The host should already be added"
    continue
  fi

  echo "Adding ${IP} to ${SSH_HOSTS}"
  ssh-keyscan -H $IP >> $SSH_HOSTS 2> /dev/null

  if [ $COPY_BOOL -eq 0 ]
  then
    ssh-copy-id "${REMOTE_USER}@${IP}"
  fi
done
set -euo pipefail

mkdir ~/ansible_logs || echo "Skipping mkdir ~/ansible_logs"

mkdir ~/env || echo "Skipping mkdir ~/env"
python3 -m venv ~/env
source ~/env/bin/activate
pip install --upgrade pip
pip install ansible

export ANSIBLE_CONFIG=$DIRECTORY/scripts/initial_ansible.cfg
until ansible-playbook $DIRECTORY/ansible_managed_node_install.yml
do
    echo "Failed initial playbook, trying again."
done
echo "Remember to run "source ~/env/bin/activate" if you did not source this script."

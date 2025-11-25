#!/bin/bash
# Description: Setup ansible-control user
# Steps: Installs python-venv, makes the user to run ansible, copies files over to new ansible user's home directory.

# Config
USER=ansible-control


# Exit on any error
set -euo pipefail


# Check permissions
if [ "$(id -u)" != "0" ]; then
    echo "Please run script as root or with sudo."
    exit 1
fi

echo "This script is meant to be run on Debian/Ubuntu-based systems."
sudo apt update
sudo apt install python3.12-venv -y


# Only run if ansible-agent does not exist
# https://stackoverflow.com/questions/14810684/check-whether-a-user-exists
if ! id "${USER}" >/dev/null 2>&1; then
    # Gets this script's directory
    SCRIPTDIRECTORY=$(dirname $0)
    echo $SCRIPTDIRECTORY

    if ! [ -d "${SCRIPTDIRECTORY}/../.git" ]; then
      echo "Please run from the cloned repo."
      exit 1
    fi

    # Create the user.
    sudo adduser --shell /usr/bin/bash $USER

    #sudo usermod -aG sudo $USER

    sudo chmod o-rwx /home/$USER
    sudo rsync -av --exclude=.git --exclude=*setup.sh $SCRIPTDIRECTORY/ /home/$USER/repo
    sudo chown -R $USER:$USER /home/$USER/repo
    echo "Successfully copied."
fi

echo "Please sign-in as ${USER} and run the ansible install script."

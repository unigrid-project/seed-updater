#!/bin/bash
# shellcheck disable=SC2034
# Copyright © 2021-2023 The Unigrid Foundation, UGD Software AB

# Check if the script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script as root."
    exit 1
fi

USER=$(logname 2>/dev/null || echo "${USER:-$(whoami)}")

echo "USER: $USER"
# Set your GitHub repository information
github_repo_hedgehog="unigrid-project/hedgehog"
github_repo_daemon="unigrid-project/daemon"
github_repo_groundhog="unigrid-project/groundhog"

# Check if jq is installed
if ! command -v jq >/dev/null 2>&1; then
    echo "jq is not installed. Attempting to install..."

    # Determine the package manager
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y jq
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y jq
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y jq
    elif command -v brew >/dev/null 2>&1; then
        brew install jq
    else
        echo "Unsupported package manager. Please install jq manually."
        exit 1
    fi
fi

# Download the specific release asset from the hedgehog GitHub repository
echo "Downloading latest hedgehog release from GitHub..."
latest_release_url_hedgehog=$(curl -s https://api.github.com/repos/${github_repo_hedgehog}/releases/latest | jq -r '.assets[] | select(.name | test("hedgehog-.*-x86_64-linux-gnu.bin")) | .browser_download_url')
curl -L -o "hedgehog.bin" "${latest_release_url_hedgehog}"

# Download the specific release asset from the daemon GitHub repository
echo "Downloading latest daemon release from GitHub..."
latest_release_url_daemon=$(curl -s https://api.github.com/repos/${github_repo_daemon}/releases/latest | jq -r '.assets[] | select(.name | test("unigrid-.*-x86_64-linux-gnu.tar.gz")) | .browser_download_url')
curl -L -o "unigrid.tar.gz" "${latest_release_url_daemon}"

# Download the specific release asset from the groundhog GitHub repository
echo "Downloading latest groundhog release from GitHub..."
latest_release_url_groundhog=$(curl -s https://api.github.com/repos/${github_repo_groundhog}/releases/latest | jq -r '.assets[] | select(.name | test("groundhog-.*-SNAPSHOT-jar-with-dependencies.jar")) | .browser_download_url')
curl -L -o "groundhog.jar" "${latest_release_url_groundhog}"

# Extract the files
echo "Extracting files..."
tar -xzf "unigrid.tar.gz"
unigrid_version=$(tar -tf unigrid.tar.gz | head -1 | cut -d/ -f1)
unigrid_directory="$(pwd)/${unigrid_version}"

# Create the /usr/local/bin/ directory if it doesn't exist
mkdir -p /usr/local/bin/

# Move the files to the /usr/local/bin/ directory
mv hedgehog.bin /usr/local/bin/
mv groundhog.jar /usr/local/bin/
mv "${unigrid_directory}/bin/unigridd" /usr/local/bin/
mv "${unigrid_directory}/bin/unigrid-cli" /usr/local/bin/

# Add execute permissions for the unigridd and unigrid-cli files
chown "${USER}":"${USER}" /usr/local/bin/unigridd
chmod +x /usr/local/bin/unigridd

chown "${USER}":"${USER}" /usr/local/bin/unigrid-cli
chmod +x /usr/local/bin/unigrid-cli

chown "${USER}":"${USER}" /usr/local/bin/hedgehog.bin
chmod +x /usr/local/bin/hedgehog.bin

chown "${USER}":"${USER}" /usr/local/bin/groundhog.jar
chmod +x /usr/local/bin/groundhog.jar

# Add the /usr/local/bin/ directory to the PATH variable if it's not already there
if ! echo "$PATH" | grep -q -E "(^|:)$HOME/.local/bin($|:)"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >>~/.bashrc
    source ~/.bashrc
fi

# Clean up downloaded files and extracted directories
echo "Cleaning up..."
rm -f "unigrid.tar.gz"
rm -rf "${unigrid_directory}"

# Define the groundhog function
groundhog_function="groundhog() {
  # Replace the path with the actual path to the groundhog JAR file
  java -jar /usr/local/bin/groundhog.jar \"\$@\"
}"

# Append the groundhog function to .bash_aliases
echo "Adding groundhog function to .bash_aliases..."
echo "${groundhog_function}" >>~/.bash_aliases

INSTALL_JAVA() {
    sudo apt-get update
    echo "Installing java"
    sudo apt-get install openjdk-17-jdk
    echo "$(java -version) "
}

# check if java is installed
if ! command -v java >/dev/null 2>&1; then
    echo "Java is not installed. Attempting to install..."
    INSTALL_JAVA
fi

# setup fail2ban
SETUP_FAIL2BAN() {
    # Enable and start the Fail2Ban service
    systemctl enable fail2ban
    systemctl start fail2ban

    # Create a custom Fail2Ban jail configuration file
    cat <<EOT >>/etc/fail2ban/jail.local
[DEFAULT]
# Ban IP addresses for 10 minutes after 5 failed login attempts
bantime  = 60m
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
backend = auto
action = %(action_)s
EOT

    # Restart Fail2Ban to apply the new configuration
    systemctl restart fail2ban

    # Display the Fail2Ban status
    fail2ban-client status

    echo "Fail2Ban has been installed (if it wasn't already) and configured successfully."
}

# Check if Fail2Ban is installed
if ! command -v fail2ban-server &>/dev/null; then
    # Update package list and install Fail2Ban
    apt update && apt install -y fail2ban
    SETUP_FAIL2BAN
else
    echo "Fail2Ban is already installed."
fi

# Download the service.sh script and save it to /usr/local/bin/ugd_service
echo "Downloading service.sh script and saving it to /usr/local/bin/ugd_service..."
curl -s -L -o "/tmp/ugd_service" "https://raw.githubusercontent.com/unigrid-project/unigrid-docker/main/scripts/service.sh"
mv "/tmp/ugd_service" "/usr/local/bin/ugd_service"
chmod +x "/usr/local/bin/ugd_service"
chown "${USER}":"${USER}" "/usr/local/bin/ugd_service"

# MOVE THE PID USED BY THE SERVICE TO THE .unigrid DIRECTORY
# Create the .unigrid directory if it doesn't exist
mkdir -p $HOME/.unigrid

# Set the PIDFILE location to the .unigrid directory
touch $HOME/.unigrid/unigrid.pid
chown "${USER}":"${USER}" $HOME/.unigrid/unigrid.pid
chmod 600 $HOME/.unigrid/unigrid.pid

touch $HOME/.unigrid/groundhog.pid
chown "${USER}":"${USER}" $HOME/.unigrid/groundhog.pid
chmod 600 $HOME/.unigrid/groundhog.pid

touch $HOME/.unigrid/hedgehog.pid
chown "${USER}":"${USER}" $HOME/.unigrid/hedgehog.pid
chmod 600 $HOME/.unigrid/hedgehog.pid

# Source .bash_aliases to make the groundhog function available immediately
echo "Sourcing .bash_aliases..."
source ~/.bash_aliases

echo "To start the unigrid daemon, run the following command:"
echo
echo "    ugd_service start"
echo
echo "To stop the unigrid daemon, run the following command:"
echo
echo "    ugd_service stop"
echo
echo "to get the status of the unigrid daemon, run the following command:"
echo
echo "    ugd_service status"
echo
echo "To restart the unigrid daemon, run the following command:"
echo
echo "    ugd_service restart"
echo
echo "To check the unigridd info, run the following command:"
echo
echo "    ugd_service unigrid getinfo"
echo
echo "To run the ugd_service in debug, run the following command:"
echo
echo "    bash -x ugd_service start"
echo

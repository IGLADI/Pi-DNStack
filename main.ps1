function Install-Ansible{
    # see https://docs.ansible.com/ansible/latest/installation_guide/installation_distros.html
    function Install-Ansible-Ubuntu-Debian {
        Write-Host "Installing Ansible on Debian-based system..."
        sudo apt update
        sudo apt install -y software-properties-common
        sudo add-apt-repository --yes --update ppa:ansible/ansible
        sudo apt install -y ansible
    }

    function Install-Ansible-RHEL {
        Write-Host "Installing Ansible on RHEL-based system..."
        sudo dnf install -y ansible
    }

    $dnfVersion = Get-Command dnf -ErrorAction SilentlyContinue
    $aptVersion = Get-Command apt -ErrorAction SilentlyContinue
    if ($dnfVersion) {
        Install-Ansible-RHEL
    } elseif ($aptVersion) {
        Install-Ansible-Ubuntu-Debian
    } else {
        Write-Host "Unsupported Linux distribution. Please install Ansible manually." -ForegroundColor Red
        exit 1
    }

    # verify installation
    $ansibleVersion = Get-Command ansible -ErrorAction SilentlyContinue
    if (-Not ($ansibleVersion)) {
        Write-Host "Ansible installation failed. Please install Ansible manually." -ForegroundColor Red
        exit 1
    } else {
        Write-Host "Ansible installed successfully." -ForegroundColor Green
    }
}

# install ansible locally
$ansibleVersion = Get-Command ansible -ErrorAction SilentlyContinue
if (-Not ($ansibleVersion)) {
    Write-Host "Ansible is not installed. Installing Ansible..."
    Install-Ansible
} else {
    Write-Host "Ansible is already installed." -ForegroundColor Green
}

# install pwsh on the remote host
Write-Host "Install PowerShell on the remote host..."
ansible-playbook -i ./inventory.ini ./install-pwsh.yml --ask-become-pass

# install docker on the remote host
Write-Host "Install Docker on the remote host..."
ansible-playbook -i ./inventory.ini ./install-docker.yml --ask-become-pass
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

    function Install-Ansible-Arch {
        Write-Host "Installing Ansible on Arch-based system..."
        sudo pacman -Sy ansible
    }

    $dnfVersion = Get-Command dnf -ErrorAction SilentlyContinue
    $aptVersion = Get-Command apt -ErrorAction SilentlyContinue
    $pacmanVersion = Get-Command pacman -ErrorAction SilentlyContinue
    if ($dnfVersion) {
        Install-Ansible-RHEL
    } elseif ($aptVersion) {
        Install-Ansible-Ubuntu-Debian
    } elseif ($pacmanVersion) {
        Install-Ansible-Arch
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

Write-Host "Install PowerShell on the remote host..."
ansible-playbook -i ./inventory.ini ./install-pwsh.yml --ask-become-pass

Write-Host "Install Docker on the remote host..."
ansible-playbook -i ./inventory.ini ./install-docker.yml --ask-become-pass

# get host information from ansible
New-Item -Path "./temp" -ItemType Directory -Force
ansible-playbook -i ./inventory.ini ./get-hosts.yml
$servers = Get-Content -Path "./temp/host_info.json" | ConvertFrom-Json
# cleanup
Remove-Item -Path "./temp" -Recurse -Force

function Get-Data {
    [hashtable]$data = Import-PowerShellDataFile -Path "./main.psd1"
    [hashtable]$defaultValues = @{
        restartPolicy = 'unless-stopped'
        stackName = 'auto_deployed'
    }
    
    # set default values for .psd1
    foreach ($key in $defaultValues.Keys) {
        if (-Not $data.ContainsKey($key)) {
            $data.Add($key, $defaultValues[$key])
        }
    }

    return $data
}

# deploy the stack on each host
# this could also easily be done with ansible
foreach ($server in $servers) {
    $hostname = ($server.msg -split ',')[0]
    $username = ($server.msg -split ',')[1]
    Write-Host "Deploying stack on $hostname..."
    $session = New-PSSession -HostName $hostname -UserName $username -SSHTransport

    $data = Get-Data

    Invoke-Command -Session $session -ScriptBlock {
        param($data)
        # pihole
        Write-Host "Deploying pihole..."
        docker run -d --name "$($data['stackName'])_pihole" --restart $data['restartPolicy'] pihole/pihole
        
        # unbound
        Write-Host "Deploying unbound..."
        # use a different image for arm devices (like Raspberry Pi)
        if ((uname -m) -eq "x86_64") {
            $unbound_image = "mvance/unbound"
        } else {
            $unbound_image = "mvance/unbound-rpi"
        }
        docker run -d --name "$($data['stackName'])_unbound" --restart $data['restartPolicy'] $unbound_image
        
        # cloudflared
        Write-Host "Deploying cloudflared..."
        docker run -d --name "$($data['stackName'])_cloudflared" --restart $data['restartPolicy'] cloudflare/cloudflared
    } -ArgumentList $data

    Remove-PSSession -Session $session
}

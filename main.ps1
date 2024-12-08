param(
    [string]$ConfigPath = "./main.psd1",
    [string]$InventoryPath = "./inventory.ini",
    [string]$TempPath = "./temp",
    [string]$become = "ask-become-pass"
)

function Install-Ansible {
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

    if (Get-Command dnf -ErrorAction SilentlyContinue) {
        Install-Ansible-RHEL
    }
    elseif (Get-Command apt -ErrorAction SilentlyContinue) {
        Install-Ansible-Ubuntu-Debian
    }
    elseif (Get-Command pacman -ErrorAction SilentlyContinue) {
        Install-Ansible-Arch
    }
    elseif ($IsWindows) {
        Write-Host "Windows not supported. Please use WSL." -ForegroundColor Red
    }
    else {
        Write-Host "Unsupported Linux distribution. Please install Ansible manually." -ForegroundColor Red
        exit 1
    }

    # verify installation
    if (-Not (Get-Command ansible -ErrorAction SilentlyContinue)) {
        Write-Host "Ansible installation failed. Please install Ansible manually." -ForegroundColor Red
        exit 1
    }
    else {
        Write-Host "Ansible installed successfully." -ForegroundColor Green
    }
}

# install ansible locally
if (-Not (Get-Command ansible -ErrorAction SilentlyContinue)) {
    Write-Host "Ansible is not installed. Installing Ansible..."
    Install-Ansible
}
else {
    Write-Host "Ansible is already installed." -ForegroundColor Green
}

# temp folder to store hosts information for pwsh remoting
New-Item -Path $TempPath -ItemType Directory -Force
# install pwsh, docker on the remote host and get hosts
Write-Host "Install dependencies on the remote host..."
# to work with $become, we need to use Invoke-Expression to pass the variable to the command
$command = "ansible-playbook -i $InventoryPath ./ansible/master.yml --$become"
Invoke-Expression $command

# get host information from ansible
[Array]$servers = Get-Content -Path "$TempPath/host_info.csv"
# cleanup
Remove-Item -Path $TempPath -Recurse -Force

function Get-Data {
    param(
        [string]$ConfigPath
    )

    if (-not (Test-Path -Path $ConfigPath)) {
        Write-Host "The specified configuration file '$ConfigPath' does not exist." -ForegroundColor Red
        exit 1
    }

    # Import data from the configuration file
    [hashtable]$data = Import-PowerShellDataFile -Path $ConfigPath

    # Define default values
    [hashtable]$defaultValues = @{
        restartPolicy      = [string]"unless-stopped"
        stackName          = [string]"auto_deployed"
        containerNetwork   = [string]"bridge"

        piholeImage        = [string]"pihole/pihole:latest"
        piholePort         = [string]"80"
        piholePassword     = [string]"admin"

        unboundEnabled     = [bool]$true
        unboundImage       = [string]"mvance/unbound:latest"
        unboundPort        = [string]"53"
        unboundConfig      = [string]"/etc/unbound/unbound.conf"

        cloudflaredEnabled = [bool]$true
        cloudflaredImage   = [string]"cloudflare/cloudflared:latest"
        cloudflaredPort    = [string]"5053"
        cloudflaredConfig  = [string]"/etc/cloudflared/config.yml"

        piholeVolumes      = [array]@("/etc/pihole:/etc/pihole", "/etc-dnsmasq.d:/etc/dnsmasq.d")
        unboundVolumes     = [array]@("/etc/unbound:/etc/unbound")
        cloudflaredVolumes = [array]@("/etc/cloudflared:/etc/cloudflared")

        commonFlags        = [string]""
        piholeFlags        = [string]""
        unboundFlags       = [string]""
        cloudflaredFlags   = [string]""
    }


    # set default values for .psd1 if not provided
    foreach ($key in $defaultValues.Keys) {
        if (-Not $data.ContainsKey($key)) {
            $data.Add($key, $defaultValues[$key])
        }
    }

    return $data
}

function Deploy-Container {
    param(
        [string]$name,
        [string]$image,
        [string]$network,
        [string]$restartPolicy,
        [string]$portMapping,
        [array]$volumes,
        [string]$flags
    )
    Write-Host "Deploying $name..."
    [string]$command = "docker run -d --name $name --restart $restartPolicy --network $network $portMapping $flags"
    foreach ($volume in $volumes) {
        $command += " -v $volume"
    }
    $command += " $image"
        
    Invoke-Expression $command
}

function Deploy-Pihole {
    param([hashtable]$data)
    Deploy-Container -name "$($data['stackName'])_pihole" `
        -image "pihole/pihole" `
        -network $data['containerNetwork'] `
        -restartPolicy $data['restartPolicy'] `
        -portMapping "-p $($data['piholePort']):80" `
        -volumes $data['piholeVolumes'] `
        -flags $data['piholeFlags']
}

function Deploy-Unbound {
    param([hashtable]$data)
    [string]$image = if ((uname -m) -eq "x86_64") { "mvance/unbound" } else { "mvance/unbound-rpi" }
    Deploy-Container -name "$($data['stackName'])_unbound" `
        -image $image `
        -network $data['containerNetwork'] `
        -restartPolicy $data['restartPolicy'] `
        -portMapping "-p $($data['unboundPort']):53" `
        -volumes $data['unboundVolumes'] `
        -flags $data['unboundFlags']
}

function Deploy-Cloudflared {
    param([hashtable]$data)
    Deploy-Container -name "$($data['stackName'])_cloudflared" `
        -image "cloudflare/cloudflared" `
        -network $data['containerNetwork'] `
        -restartPolicy $data['restartPolicy'] `
        -portMapping "-p $($data['cloudflaredPort']):5053" `
        -volumes $data['cloudflaredVolumes'] `
        -flags $data['cloudflaredFlags']
}

# store the functions in variables to send them to the remote host
# based on https://stackoverflow.com/questions/11367367/how-do-i-include-a-locally-defined-function-when-using-powershells-invoke-comma#:~:text=%24fooDef%20%3D%20%22function%20foo%20%7B%20%24%7Bfunction%3Afoo%7D%20%7D%22%0A%0AInvoke%2DCommand%20%2DArgumentList%20%24fooDef%20%2DComputerName%20someserver.example.com%20%2DScriptBlock%20%7B%0A%20%20%20%20Param(%20%24fooDef%20)%0A%0A%20%20%20%20.%20(%5BScriptBlock%5D%3A%3ACreate(%24fooDef))%0A%0A%20%20%20%20Write%2DHost%20%22You%20can%20call%20the%20function%20as%20often%20as%20you%20like%3A%22%0A%20%20%20%20foo%20%22Bye%22%0A%20%20%20%20foo%20%22Adieu!%22%0A%7D
[string]$deployContainer = "function Deploy-Container {`n" + 
                   (Get-Command Deploy-Container).ScriptBlock.ToString() + 
"`n}"
[string]$deployPihole = "function Deploy-Pihole {`n" + 
                (Get-Command Deploy-Pihole).ScriptBlock.ToString() + 
"`n}"
[string]$deployUnbound = "function Deploy-Unbound {`n" + 
                 (Get-Command Deploy-Unbound).ScriptBlock.ToString() + 
"`n}"
[string]$deployCloudflared = "function Deploy-Cloudflared {`n" + 
                     (Get-Command Deploy-Cloudflared).ScriptBlock.ToString() + 
"`n}"

# deploy the stack on each host
# deploying itself could be done trough ansible, but we will use PowerShell to make further changes
foreach ($server in $servers) {
    # make an ssh connection to the remote host
    [string]$hostname, $username = $server -split ','
    $session = New-PSSession -HostName $hostname -UserName $username -SSHTransport
    
    # get the data from the .psd1 file
    [hashtable]$data = Get-Data -ConfigPath $ConfigPath --$become
    
    # deploy the stack on the remote host
    Invoke-Command -Session $session -ScriptBlock {
        param([hashtable]$data, [string]$deployContainer, [string]$deployPihole, [string]$deployUnbound, [string]$deployCloudflared)
        # recreate the functions on the remote host
        . ([ScriptBlock]::Create($deployContainer))
        . ([ScriptBlock]::Create($deployPihole))
        . ([ScriptBlock]::Create($deployUnbound))
        . ([ScriptBlock]::Create($deployCloudflared))

        # pihole
        Deploy-Pihole -data $data
        
        # unbound
        if ($data['unboundEnabled']) {
            Deploy-Unbound -data $data
        }
        else {
            Write-Host "Unbound is disabled."
        }
        
        # cloudflared
        if ($data['cloudflaredEnabled']) {
            Deploy-Cloudflared -data $data
        }
        else {
            Write-Host "Cloudflared is disabled."
        }
    } -ArgumentList $data, $deployContainer, $deployPihole, $deployUnbound, $deployCloudflared
    
    # cleanup
    Remove-PSSession -Session $session
}
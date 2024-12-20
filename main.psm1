# powershell does not seem to support -ErrorAction Stop on external commands so we need to manually check the exit code of each command, this is a wrapper for it
function Invoke-CommandWithCheck {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )
    # we need the catch block to catch the error msg: $_
    try {
        # $($_.Exception.Message) does not work properly with external commands so we need to store the whole output to print it on error
        # 2>&1 redirects stderr to stdout see https://www.youtube.com/watch?v=zMKacHGuIHI as = in pwsh only takes the stdout stream
        $output = Invoke-Expression "$Command 2>&1"
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code $LASTEXITCODE : $Command"
        }
    }
    catch {
        throw "Error executing command: `"$Command`" Error: `"$output`""
    }
}

function Install-Ansible {
    # see https://docs.ansible.com/ansible/latest/installation_guide/installation_distros.html
    if (Get-Command dnf -ErrorAction SilentlyContinue) {
        # rhel using dnf
        Write-Host "Installing Ansible on RHEL-based system..."
        Invoke-CommandWithCheck "sudo dnf install -y ansible"
    }
    elseif (Get-Command apt -ErrorAction SilentlyContinue) {
        # debian/ubuntu using apt
        Write-Host "Installing Ansible on Debian-based system..."
        try {
            Invoke-CommandWithCheck "sudo apt update"
            Invoke-CommandWithCheck "sudo apt install -y software-properties-common"
            Invoke-CommandWithCheck "sudo add-apt-repository --yes --update ppa:ansible/ansible"
            Invoke-CommandWithCheck "sudo apt install -y ansible"
        }
        catch {
            throw "Error installing Ansible with apt."
        }
    }
    elseif (Get-Command pacman -ErrorAction SilentlyContinue) {
        # arch using pacman
        Write-Host "Installing Ansible on Arch-based system..."
        try {
            Invoke-CommandWithCheck "sudo pacman -Sy ansible"
        }
        catch {
            throw "Error installing Ansible with pacman."
        }
    }
    elseif ($IsWindows) {
        throw "Windows not supported. Please use WSL."
    }
    else {
        throw "Unsupported Linux distribution. Please install Ansible manually."
    }

    # verify installation
    if (-Not (Get-Command ansible -ErrorAction SilentlyContinue)) {
        throw "Ansible installation failed. Please install Ansible manually."
    }
    else {
        Write-Host "Ansible installed successfully." -ForegroundColor Green
    }
}


function Get-Data {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    # import data from the psd1 file
    [hashtable]$data = Import-PowerShellDataFile -Path $ConfigPath

    return $data
}

function Deploy-Container {
    param(
        [Parameter(Mandatory = $true)]
        [string]$name,
        [Parameter(Mandatory = $true)]
        [string]$image,
        [Parameter(Mandatory = $false)]
        [string]$network,
        [Parameter(Mandatory = $false)]
        [string]$restartPolicy,
        [Parameter(Mandatory = $false)]
        [array]$ports,
        [Parameter(Mandatory = $false)]
        [array]$volumes,
        [Parameter(Mandatory = $false)]
        [string]$flags = "",
        [Parameter(Mandatory = $false)]
        [string]$extra = ""
    )
    Write-Host "Deploying $name..." 
    [string]$command = "docker run -d --name $name"
    if ($restartPolicy) { 
        $command += " --restart $restartPolicy" 
    }
    if ($network) { 
        $command += " --network $network" 
    }

    foreach ($port in $ports) {
        $command += " -p $port"
    }

    foreach ($volume in $volumes) {
        $command += " -v $volume"
    }

    $command += " $flags $image $extra"

    Invoke-Expression $command
}

function Deploy-Pihole {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$data)

    [string]$password = $data['piholePassword']
    if ($password -eq "admin") {
        Write-Host "Warning: The default password is used." -ForegroundColor Red
    }

    Deploy-Container -name "$($data['stackName'])_pihole" `
        -image "pihole/pihole" `
        -network $data['containerNetwork'] `
        -restartPolicy $data['restartPolicy'] `
        -ports @(
        "$($data['piholeUiPort']):80",
        "$($data['piholeDnsPort']):53"
    ) `
        -volumes $data['piholeVolumes'] `
        -flags "$($data['piholeFlags']) -e WEBPASSWORD=$password"
}

function Deploy-Unbound {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$data)
    # choose the image based on arm or x86
    [string]$image = if ((uname -m) -eq "x86_64") { $data['unboundImage'] } else { $data['unboundArmImage'] }

    Deploy-Container -name "$($data['stackName'])_unbound" `
        -image $image `
        -network $data['containerNetwork'] `
        -restartPolicy $data['restartPolicy'] `
        -ports @("$($data['unboundPort']):53") `
        -volumes $data['unboundVolumes'] `
        -flags $data['unboundFlags']
}

function Deploy-Cloudflared {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$data)

    Deploy-Container -name "$($data['stackName'])_cloudflared" `
        -image "cloudflare/cloudflared" `
        -network $data['containerNetwork'] `
        -restartPolicy $data['restartPolicy'] `
        -ports @("$($data['cloudflaredPort']):5053") `
        -volumes $data['cloudflaredVolumes'] `
        -flags $data['cloudflaredFlags'] `
        -extra "proxy-dns --port 5053 --address 0.0.0.0"
}

function Set-PiholeConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$data)

    Write-Host "Configuring Pi-hole to use the correct upstream DNS servers..."

    function Get-DockerNetwork {
        param([hashtable]$data,
            [string]$container,
            [string]$port)
        
        # see https://stackoverflow.com/questions/17157721/how-to-get-a-docker-containers-ip-address-from-the-host
        [string]$IP = Invoke-CommandWithCheck "docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ""$($data['stackName'])_$container"""
        # inner port so no need to take it from the .psd1 file
        [string]$Network = "$IP#$port"
        return $Network
    }

    # get ips of upstream DNS servers as pihole needs ip addresses and not docker hostnames
    try {
        if ($data['unboundEnabled']) {
            [string]$unboundNetwork = Get-DockerNetwork -data $data -container "unbound" -port "53"
        }
        if ($data['cloudflaredEnabled']) {
            [string]$cloudflaredNetwork = Get-DockerNetwork -data $data -container "cloudflared" -port "5053"
        }
    }
    catch {
        throw "Error getting IP addresses: $_"
    }

    function Set-DnsConfiguration {
        param(
            [Parameter(Mandatory = $true)]
            [hashtable]$data,
            [Parameter(Mandatory = $true)]
            [string]$nr,
            [Parameter(Mandatory = $true)]
            [string]$dnsNetwork
        )

        # update pihole's upstream DNS servers
        # add line if it doesn't exist else update itself
        # with help of https://chatgpt.com/share/67604d61-1d44-8011-99dd-83e8538cd7af
        $command = @"
    if grep -q '^PIHOLE_DNS_$nr=' /etc/pihole/setupVars.conf; then
        sed -i '/^PIHOLE_DNS_$nr=/c\PIHOLE_DNS_$nr=$dnsNetwork' /etc/pihole/setupVars.conf
    else
        echo 'PIHOLE_DNS_$nr=$dnsNetwork' >> /etc/pihole/setupVars.conf
    fi
"@
        docker exec "$($data['stackName'])_pihole" /bin/bash -c $command
    }

    [int]$nr = 1

    try {
        foreach ($dns in $data['extraDNS']) {
            Set-DnsConfiguration -data $data -nr $nr -dnsNetwork $dns
            $nr++
        }
        if ($data['unboundEnabled']) {
            Set-DnsConfiguration -data $data -nr $nr -dnsNetwork $unboundNetwork
            $nr++
        }
        if ($data['cloudflaredEnabled']) {
            Set-DnsConfiguration -data $data -nr $nr -dnsNetwork $cloudflaredNetwork
            $nr++
        }
    }
    catch {
        throw "Get-Error updating Pi-hole configuration: $_"
    }

    function Remove-Old-DnsConfiguration {
        param(
            [Parameter(Mandatory = $true)]
            [hashtable]$data,
            [Parameter(Mandatory = $true)]
            [int]$nr
        )

        # remove all dns with a nr higher than $nr
        # with help of https://chatgpt.com/share/676050bc-c4bc-8011-aeec-5efcce256287
        do {
            [string]$command = "sed -i '/^PIHOLE_DNS_$nr=/d' /etc/pihole/setupVars.conf"
            [string]$output = docker exec "$($data['stackName'])_pihole" /bin/bash -c "grep '^PIHOLE_DNS_$nr=' /etc/pihole/setupVars.conf"

            if ($output) {
                docker exec "$($data['stackName'])_pihole" /bin/bash -c $command
                $nr++
            }
        } while ($output)
    }

    Remove-Old-DnsConfiguration -data $data -nr $nr
}

function Get-FunctionDefinitions {
    # store the functions in variables to send them to the remote host
    # based on https://stackoverflow.com/questions/11367367/how-do-i-include-a-locally-defined-function-when-using-powershells-invoke-comma#:~:text=%24fooDef%20%3D%20%22function%20foo%20%7B%20%24%7Bfunction%3Afoo%7D%20%7D%22%0A%0AInvoke%2DCommand%20%2DArgumentList%20%24fooDef%20%2DComputerName%20someserver.example.com%20%2DScriptBlock%20%7B%0A%20%20%20%20Param(%20%24fooDef%20)%0A%0A%20%20%20%20.%20(%5BScriptBlock%5D%3A%3ACreate(%24fooDef))%0A%0A%20%20%20%20Write%2DHost%20%22You%20can%20call%20the%20function%20as%20often%20as%20you%20like%3A%22%0A%20%20%20%20foo%20%22Bye%22%0A%20%20%20%20foo%20%22Adieu!%22%0A%7D
    param(
        [Parameter(Mandatory = $true)]
        [array]$functions)
    [array]$functionsDefinitions = @()
    foreach ($function in $functions) {
        $functionsDefinitions += "function $function { `n" + 
            (Get-Command $function).ScriptBlock.ToString() +
        "`n}"
    }

    return $functionsDefinitions
}
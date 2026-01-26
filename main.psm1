# Disclaimer: most function comments are made with the help of copilot

#region Helper Functions
<#
.SYNOPSIS
    Executes a command and validates its exit code.
.DESCRIPTION
    Wrapper function that executes external commands and checks their exit codes.
    Powershell does not support -ErrorAction Stop for external commands so we need to check the exit code manually.
.PARAMETER Command
    The command string to execute.
.EXAMPLE
    Invoke-CommandWithCheck "docker ps"
#>
function Invoke-CommandWithCheck {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )
    try {
        # $($_.Exception.Message) does not work properly with external commands so we need to store the whole output to print it on error
        # 2>&1 redirects stderr to stdout see https://www.youtube.com/watch?v=zMKacHGuIHI as "=" only takes the stdout stream
        $output = Invoke-Expression "$Command 2>&1"
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code $LASTEXITCODE : $Command"
        }
        return $output
    }
    catch {
        throw "Error executing command: `"$Command`" Error: `"$output`""
    }
}

<#
.SYNOPSIS
    Gets function definitions for remote execution.
.DESCRIPTION
    Prepares function definitions to be sent to remote hosts for execution.
    Required for PowerShell remoting when functions need to be recreated on target hosts (aka import the local module to the remote session).
    Based on https://stackoverflow.com/questions/11367367/how-do-i-include-a-locally-defined-function-when-using-powershells-invoke-comma#:~:text=%24fooDef%20%3D%20%22function%20foo%20%7B%20%24%7Bfunction%3Afoo%7D%20%7D%22%0A%0AInvoke%2DCommand%20%2DArgumentList%20%24fooDef%20%2DComputerName%20someserver.example.com%20%2DScriptBlock%20%7B%0A%20%20%20%20Param(%20%24fooDef%20)%0A%0A%20%20%20%20.%20(%5BScriptBlock%5D%3A%3ACreate(%24fooDef))%0A%0A%20%20%20%20Write%2DHost%20%22You%20can%20call%20the%20function%20as%20often%20as%20you%20like%3A%22%0A%20%20%20%20foo%20%22Bye%22%0A%20%20%20%20foo%20%22Adieu!%22%0A%7D
.PARAMETER functions
    Array of function names to prepare for remote execution.
.EXAMPLE
    Get-FunctionDefinitions -functions @("Deploy-Container", "Deploy-Pihole")
#>
function Get-FunctionDefinitions {
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
#endregion

#region Configuration Management
<#
.SYNOPSIS
    Checks if container configuration differs from desired state.
.DESCRIPTION
    Compares current container configuration with desired configuration parameters.
    Used for declarative container management.
.PARAMETER CurrentConfig
    Hashtable containing current container configuration.
.PARAMETER image, restartPolicy, containerNetwork, ports, volumes, envs
    Desired configuration parameters to compare against.
.EXAMPLE
    ConfigDifferent -CurrentConfig $config -image "nginx:latest" -restartPolicy "always" -containerNetwork "bridge"
#>
function ConfigDifferent {
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$CurrentConfig,
        [Parameter(Mandatory = $true)]
        [string]$image,
        [Parameter(Mandatory = $true)]
        [string]$restartPolicy,
        [Parameter(Mandatory = $true)]
        [string]$containerNetwork,
        [Parameter(Mandatory = $false)]
        [array]$ports = @(),
        [Parameter(Mandatory = $false)]
        [array]$volumes = @(),
        [Parameter(Mandatory = $false)]
        [array]$envs = @()
    )

    if ($CurrentConfig.Image -ne $image) {
        return $true
    }

    if ($CurrentConfig.RestartPolicy -ne $restartPolicy) {
        return $true
    }

    if ($CurrentConfig.ContainerNetwork -ne $containerNetwork) {
        return $true
    }

    # check if all ports we want are mapped
    foreach ($port in $ports) {
        if (-Not ($CurrentConfig.Ports -Match $port)) {
            if ($port -match '^\d+:') {
                return $true
            }
        }
    }
    # check if no extra ports are mapped
    foreach ($port in ($CurrentConfig.Ports -split ' ')) {
        if (-Not ($ports -Match $port)) {
            return $true
        }
    }

    # check if all volumes we want are mounted
    foreach ($volume in $volumes) {
        if (-Not ($CurrentConfig.Volumes -Match $volume)) {
            return $true
        }
    }
    # check if no extra volumes are mounted
    foreach ($volume in ($CurrentConfig.Volumes -split ' ')) {
        if (-Not ($volumes -Match $volume)) {
            return $true
        }
    }

    # check if all env variables we want are set
    foreach ($env in $envs) {
        if (-Not ($CurrentConfig.EnvironmentVariables -Match $env)) {
            return $true
        }
    }
    # we don't need to check visa versa as as there is only the pihole password as env variable
    # SSH connection
    [string]$hostname, $username = $server -split ','
    return $false
}

<#
.SYNOPSIS
    Retrieves current container configuration.
.DESCRIPTION
    Gets configuration details of an existing container using Docker inspect commands.
.PARAMETER ContainerName
    Name of the container to inspect.
.EXAMPLE
    Get-CurrentContainerConfig -ContainerName "pihole"
#>
function Get-CurrentContainerConfig {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,
        [Parameter(Mandatory = $false)]
        [string]$containerEngine = "docker"
    )

    # Corrected: Use Invoke-Expression for the ps command to avoid parser errors with the variable
    if ($null -eq (Invoke-Expression "$containerEngine ps --filter 'name=$ContainerName' --format '{{.Names}}'")) {
        return $null
    }

    [string]$image = Invoke-Expression "$containerEngine inspect --format='{{.Config.Image}}' $ContainerName"
    # with help of https://chatgpt.com/share/6766e1f1-a8a0-8011-b306-59da137b7359
    [string]$ports = Invoke-Expression "$containerEngine inspect --format '{{range `$p, `$conf := .NetworkSettings.Ports}}{{if `$conf}}{{(index `$conf 0).HostPort}}:{{(index `$conf 0).HostPort}} {{end}}{{end}}' $ContainerName"
    [string]$volumes = Invoke-Expression "$containerEngine inspect --format '{{range .Mounts}}{{if .Source}}{{.Source}}:{{.Destination}} {{end}}{{end}}' $ContainerName"
    [string]$environmentVariables = Invoke-Expression "$containerEngine inspect --format='{{range .Config.Env}}{{.}}{{end}}' $ContainerName"
    [string]$restartPolicy = Invoke-Expression "$containerEngine inspect --format='{{.HostConfig.RestartPolicy.Name}}' $ContainerName"
    [string]$containerNetwork = Invoke-Expression "$containerEngine inspect --format '{{.HostConfig.NetworkMode}}' $ContainerName"

    [hashtable]$currentConfig = @{
        Image                = $image
        Ports                = $ports
        Volumes              = $volumes
        EnvironmentVariables = $environmentVariables
        RestartPolicy        = $restartPolicy
        ContainerNetwork     = $containerNetwork
    }

    return $currentConfig
}
#endregion

#region Deployment Functions
<#
.SYNOPSIS
    Generic container deployment function.
.DESCRIPTION
    Handles container deployment with support for various configuration options.
    Implements declarative deployment pattern.
.PARAMETER name, image, network, restartPolicy, ports, volumes, flags, extra
    Container configuration parameters.
.EXAMPLE
    Deploy-Container -name "pihole" -image "pihole/pihole:latest" -network "bridge"
#>
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
        [string]$extra = "",
        [Parameter(Mandatory = $false)]
        [string]$containerEngine = "docker"
    )
    
    try {
        # declarative checks
        $currentConfig = Get-CurrentContainerConfig -ContainerName $name -containerEngine $containerEngine
        $envs = @()
        if ($name -match "pihole") {
            $envs += "FTLCONF_webserver_api_password=$($data['piholePassword'])"
        }
        # check if the container runs
        if ($null -eq $currentConfig) {
            Write-Host "Deploying $name..." 
        }
        # checks if there are configuration differences between the current and desired state
        elseif (ConfigDifferent -CurrentConfig $currentConfig -image $image -ports $ports -volumes $volumes -envs $envs -restartPolicy $restartPolicy -containerNetwork $network) {
            Write-Host "Container $name exists but configuration differs. Replacing container..."
            Invoke-Expression "$containerEngine rm -f $name"
        }
        else {
            Write-Host "Container $name is already deployed with the correct configuration."
            return
        }

        [string]$command = "$containerEngine run -d --name $name"
        if ($restartPolicy) { 
            $command += " --restart $restartPolicy" 
        }
        if ($network) { 
            $command += " --network $network" 
        }

        foreach ($port in $ports) {
            # with help of https://chatgpt.com/share/67669ebb-9d50-8011-a317-88c6aa993d1d
            # if there is an outwards port map it
            if ($port -match '^\d+:') {
                $command += " -p $port"
            }
        }

        foreach ($volume in $volumes) {
            $command += " -v $volume"
        }

        $command += " $flags $image $extra >/dev/null"

        # not Invoke-CommandWithCheck as we don't execute this in the main thread and is not worthit to also reacreate this function
        Invoke-Expression $command
    }
    catch {
        throw "Failed to deploy container $name : $_"
    }
}

<#
.SYNOPSIS
    Deploys Pi-hole container.
.DESCRIPTION
    Specialized deployment function for Pi-hole.
.PARAMETER data
    Configuration hashtable including Pi-hole specific settings.
.EXAMPLE
    Deploy-Pihole -data $config
#>
function Deploy-Pihole {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$data)

    [string]$password = $data['piholePassword']

    Deploy-Container -name "$($data['stackName'])_pihole" `
        -image "pihole/pihole" `
        -network $data['containerNetwork'] `
        -restartPolicy $data['restartPolicy'] `
        -ports @(
        "$($data['piholeUiPort']):80",
        "$($data['piholeDnsPort']):53"
    ) `
        -volumes $data['piholeVolumes'] `
        -flags "$($data['piholeFlags']) -e FTLCONF_webserver_api_password=$password" `
        -containerEngine $data['containerEngine']
}

<#
.SYNOPSIS
    Deploys Unbound DNS resolver.
.DESCRIPTION
    Specialized deployment function for Unbound .
.PARAMETER data
    Configuration hashtable including Unbound specific settings.
.EXAMPLE
    Deploy-Unbound -data $config
#>
function Deploy-Unbound {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$data)
    # Choose the correct image based on cpu architecture
    [string]$image = if ((uname -m) -eq "x86_64") { $data['unboundImage'] } else { $data['unboundArmImage'] }

    Deploy-Container -name "$($data['stackName'])_unbound" `
        -image $image `
        -network $data['containerNetwork'] `
        -restartPolicy $data['restartPolicy'] `
        -ports @("$($data['unboundPort']):53") `
        -volumes $data['unboundVolumes'] `
        -flags $data['unboundFlags'] `
        -containerEngine $data['containerEngine']
}  

<#
.SYNOPSIS
    Deploys Cloudflared DNS-over-HTTPS proxy.
.DESCRIPTION
    Specialized deployment function for Cloudflared.
.PARAMETER data
    Configuration hashtable including Cloudflared specific settings.
.EXAMPLE
    Deploy-Cloudflared -data $config
#>
function Deploy-Cloudflared {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$data)

    $extra = "proxy-dns --port 5053 --address 0.0.0.0"
    if (-not $data['cloudflaredUpstream'] -eq "") {
        $extra += " --upstream $data['cloudflaredUpstream']"
    }
    
    Deploy-Container -name "$($data['stackName'])_cloudflared" `
        -image "cloudflare/cloudflared" `
        -network $data['containerNetwork'] `
        -restartPolicy $data['restartPolicy'] `
        -ports @("$($data['cloudflaredPort']):5053") `
        -volumes $data['cloudflaredVolumes'] `
        -flags $data['cloudflaredFlags'] `
        -extra $extra `
        -containerEngine $data['containerEngine']
}

<#
.SYNOPSIS
    Removes disabled containers.
.DESCRIPTION
    Removes Unbound and Cloudflared containers if they are disabled in configuration.
.PARAMETER data
    Configuration hashtable including service enable/disable flags.
.EXAMPLE
    Remove-OldContainers -data $config
#>
function Remove-OldContainers {
    param(
        [Parameter(Mandatory = $false)]
        [hashtable]$data
    )

    if (-Not $data['unboundEnabled']) {
        Write-Host "Removing old unbound container if present..."
        # remove the container silently
        Invoke-Expression "$($data['containerEngine']) rm -f $($data['stackName'])_unbound 2>&1 >/dev/null"
    }

    if (-Not $data['cloudflaredEnabled']) {
        Write-Host "Removing old cloudflared container if present..."
        Invoke-Expression "$($data['containerEngine']) rm -f $($data['stackName'])_cloudflared 2>&1 >/dev/null"
    }
}
#endregion

#region Configuration Functions
<#
.SYNOPSIS
    Configures Pi-hole settings.
.DESCRIPTION
    Applies Pi-hole configuration including DNS servers, DNSSEC, adlists, and interface settings.
.PARAMETER data
    Configuration hashtable including Pi-hole settings.
.EXAMPLE
    Set-PiholeConfiguration -data $config
#>
function Set-PiholeConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$data)

    Write-Host "Configuring Pi-hole..."

    function Get-DockerNetwork {
        param([hashtable]$data,
            [string]$container,
            [string]$port)
        
        # https://stackoverflow.com/questions/17157721/how-to-get-a-docker-containers-ip-address-from-the-host
        try {
            if ($data['containerNetwork'] -eq "host") {
                [string]$IP = Invoke-CommandWithCheck "hostname -I | awk '{print `$1}'"
            }
            else {
                [string]$IP = Invoke-CommandWithCheck "$($data['containerEngine']) inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ""$($data['stackName'])_$container"""
            }
            if (-not $IP) {
                throw "Failed to get IP address for container $container"
            }
            return "$IP#$port"
        }
        catch {
            throw "Failed to get network settings for $container : $_"
        }
    }

    # region upsteam DNS
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
        # add line if it doesn't exist else update it
        # with help of https://chatgpt.com/share/67604d61-1d44-8011-99dd-83e8538cd7af
        $command = @"
    if grep -q '^PIHOLE_DNS_$nr=' /etc/pihole/setupVars.conf; then
        sed -i '/^PIHOLE_DNS_$nr=/c\PIHOLE_DNS_$nr=$dnsNetwork' /etc/pihole/setupVars.conf
    else
        echo 'PIHOLE_DNS_$nr=$dnsNetwork' >> /etc/pihole/setupVars.conf
    fi
"@
        Invoke-Expression "$($data['containerEngine']) exec $($data['stackName'])_pihole /bin/bash -c '$command'"
    }

    Write-Host "Waiting for Pi-hole to be healthy..."
    $maxRetries = 30
    $retryCount = 0
    $healthy = $false
    while ($retryCount -lt $maxRetries -and -not $healthy) {
        Start-Sleep -Seconds 10
        $status = Invoke-Expression "$($data['containerEngine']) inspect --format='{{.State.Health.Status}}' $($data['stackName'])_pihole"
        if ($status -eq "healthy") {
            $healthy = $true
        }
        else {
            $retryCount++
            Write-Host "Pi-hole is not healthy yet. Retrying... ($retryCount/$maxRetries)"
        }
    }
    if (-not $healthy) {
        throw "Pi-hole did not become healthy within the expected time."
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
        throw "Failed to configure Pi-hole DNS settings: $_"
    }
    
    # remove all dns with a nr higher than $nr aka outdated upstream DNS servers
    # with help of https://chatgpt.com/share/676050bc-c4bc-8011-aeec-5efcce256287
    do {
        [string]$command = "sed -i '/^PIHOLE_DNS_$nr=/d' /etc/pihole/setupVars.conf"
        [string]$output = Invoke-Expression "$($data['containerEngine']) exec $($data['stackName'])_pihole /bin/bash -c `"grep '^PIHOLE_DNS_$nr=' /etc/pihole/setupVars.conf`""

        if ($output) {
            Invoke-Expression "$($data['containerEngine']) exec $($data['stackName'])_pihole /bin/bash -c '$command'"
            $nr++
        }
    } while ($output)
    # endregion

    #region dnssec
    $dnssecValue = if ($data['DNSSECEnabled']) { 'true' } else { 'false' }

    # w help of https://chatgpt.com/share/676ad29c-8da4-8011-bb80-e9c2b8ed9019
    $command = @"
if grep -q '^DNSSEC=' /etc/pihole/setupVars.conf; then
    sed -i 's/^DNSSEC=.*/DNSSEC=$dnssecValue/' /etc/pihole/setupVars.conf
else
    echo 'DNSSEC=$dnssecValue' >> /etc/pihole/setupVars.conf
fi
"@
    Invoke-Expression "$($data['containerEngine']) exec $($data['stackName'])_pihole /bin/bash -c '$command'"
    #endregion

    #region adlist
    # update gravity in case the db is not yet created
    Invoke-Expression "$($data['containerEngine']) exec $($data['stackName'])_pihole pihole updateGravity 2>&1 >/dev/null"
    # remove deprecated adlists
    $existingAdlists = Invoke-Expression "$($data['containerEngine']) exec $($data['stackName'])_pihole pihole-FTL sqlite3 /etc/pihole/gravity.db 'SELECT address FROM adlist;'"
    $existingAdlists = $existingAdlists -split "`n"

    foreach ($adlist in $existingAdlists) {
        if ($adlist -notin $data['adlists']) {
            Invoke-Expression "$($data['containerEngine']) exec $($data['stackName'])_pihole pihole-FTL sqlite3 /etc/pihole/gravity.db 'DELETE FROM adlist WHERE address=`'$adlist`';'"
        }
    }
    # add new ones
    foreach ($adlist in $data['adlists']) {
        $command = @"
INSERT OR IGNORE INTO adlist (address, enabled, date_added, date_modified, comment, date_updated, number, invalid_domains, status)
VALUES ('$adlist', 1, cast(strftime('%s', 'now') as int), cast(strftime('%s', 'now') as int), 'Added via Pi-DNStack', NULL, 0, 0, 0);
"@
        Invoke-Expression "$($data['containerEngine']) exec $($data['stackName'])_pihole pihole-FTL sqlite3 /etc/pihole/gravity.db '$command'"

    }
    Invoke-Expression "$($data['containerEngine']) exec $($data['stackName'])_pihole pihole updateGravity 2>&1 >/dev/null"
    #endregion

    #region set pihole interface
    # w help of https://chatgpt.com/share/676c02af-26f4-8011-8766-8374c08aeb23
    $command = $command = @"
if [[ -n "$($data['interface'])" ]]; then
    if grep -q "^PIHOLE_INTERFACE=" /etc/pihole/setupVars.conf; then
        sed -i "s/^PIHOLE_INTERFACE=.*/PIHOLE_INTERFACE=$($data['interface'])/" /etc/pihole/setupVars.conf
    else
        echo "PIHOLE_INTERFACE=$($data['interface'])" >> /etc/pihole/setupVars.conf
    fi
fi

if [[ -n "$($data['listen'])" ]]; then
    if grep -q "^DNSMASQ_LISTENING=" /etc/pihole/setupVars.conf; then
        sed -i "s/^DNSMASQ_LISTENING=.*/DNSMASQ_LISTENING=$($data['listen'])/" /etc/pihole/setupVars.conf
    else
        echo "DNSMASQ_LISTENING=$($data['listen'])" >> /etc/pihole/setupVars.conf
    fi
fi
"@

    Invoke-Expression "$($data['containerEngine']) exec $($data['stackName'])_pihole /bin/bash -c '$command'"
    #endregion
}

<#
.SYNOPSIS
    Installs Ansible if not present.
.DESCRIPTION
    Detects operating system and installs Ansible using appropriate package manager.
    Supports apt, dnf, and pacman package managers.
.EXAMPLE
    Install-Ansible
#>
function Install-Ansible {
    # https://docs.ansible.com/ansible/latest/installation_guide/installation_distros.html
    if (-Not (Get-Command ansible -ErrorAction SilentlyContinue)) {
        Write-Host "Ansible is not installed. Installing Ansible..."
        if (Get-Command dnf -ErrorAction SilentlyContinue) {
            Write-Host "Installing Ansible on RHEL-based system..."
            Invoke-CommandWithCheck "sudo dnf install -y ansible"
        }
        elseif (Get-Command apt -ErrorAction SilentlyContinue) {
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
    else {
        Write-Host "Ansible is already installed." -ForegroundColor Green
    }
}

<#
.SYNOPSIS
    Installs dependencies on remote hosts.
.DESCRIPTION
    Uses Ansible to install required dependencies (Docker, PowerShell) on remote hosts.
.PARAMETER TempPath
    Path for temporary files.
.PARAMETER InventoryPath
    Path to Ansible inventory file.
.PARAMETER become
    Ansible privilege escalation method.
.EXAMPLE
    Install-DependenciesRemotely -TempPath "./temp" -InventoryPath "./inventory.ini" -become "ask-become-pass"
#>
function Install-DependenciesRemotely { 
    param(
        [Parameter(Mandatory = $true)]
        [string]$TempPath,
        [Parameter(Mandatory = $true)]
        [string]$InventoryPath,
        [Parameter(Mandatory = $true)]
        [string]$become
    )

    # temp folder to store hosts information for pwsh remoting
    New-Item -Path $TempPath -ItemType Directory -Force
    # Install Powershell & Docker on the remote host and get hosts information
    Write-Host "Install dependencies on the remote host..."
    [string]$command = "ansible-playbook -i $InventoryPath ./ansible/master.yml --$become"
    try {
        Invoke-CommandWithCheck $command
    }
    catch {
        if ($_.Exception.Message -match "Incorrect sudo password") {
            throw "Error: Incorrect sudo password"
        }
        else {
            throw $($_.Exception.Message)
        }
    }
}
#endregion

#region Client Configuration
<#
.SYNOPSIS
    Gets the Pi-Hol IP address.
.DESCRIPTION
    Retrieves the DNS IP address based on the configuration.
    If the Pi-hole DNS port is published outside the container, the host IP is used.
    Otherwise, the container IP is used.
.PARAMETER data
    Configuration hashtable including Pi-hole settings.
.EXAMPLE
    Get-DnsIp -data $config
#>
function Get-DnsIp {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$data
    )

    # Check if piholeDnsPort is published outside the container
    if ($data['containerNetwork'] -eq "host") {
        # Use host ip
        return Invoke-CommandWithCheck "hostname -I | awk '{print `$1}'"

    }
    else {
        # Use container ip, not recommended as it will not be accessible from outside
        return Invoke-CommandWithCheck "$($data['containerEngine']) inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $($data['stackName'])_pihole"
    }
}

<#
.SYNOPSIS
    Updates DHCP settings to use Pi-DNStack.
.DESCRIPTION
    Configures windows DHCP server to use Pi-hole as the primary DNS server.
    Supports server-wide, scope-specific, and policy-specific configurations.
.PARAMETER data
    Configuration hashtable including DHCP settings.
.PARAMETER dnsServer
    DNS server IP address.
.EXAMPLE
    Update-DHCPSettings -data $config -dnsServer @("127.0.0.1")
#>
function Update-DHCPSettings {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$data,
        [Parameter(Mandatory = $true)]
        [array]$dnsServer
    )

    Write-Host "Configuring DHCP to use Pi-DNStack..."

    if (-not $dnsServer) {
        throw "DNS server not found."
    }

    for ($i = 0; $i -lt $data['dhcpServer'].Length; $i++) {
        $server = $data['dhcpServer'][$i]
        $username = $data['dhcpUser'][$i]
        # Create a SSH (because we connect from a linux host) PowerShell session to the DHCP server
        try {
            $session = New-PSSession -HostName $server -UserName $username -SSHTransport -ErrorAction Stop
        }
        catch {
            throw "Failed to create SSH session to DHCP server $server : $_"
        }

        # per https://github.com/PowerShell/PowerShell/issues/16382 https://stackoverflow.com/questions/78763548/powershell-is-unable-to-load-shared-library-libmi-for-error-message-on-alpine
        # try can work but may fail to catch for Set-DhcpServerv4OptionValue
        try {
            Invoke-Command -Session $session -ScriptBlock {
                param(
                    [Parameter(Mandatory = $true)]
                    [string]$dnsServer,
                    [Parameter(Mandatory = $false)]
                    [string]$scopeId,
                    [Parameter(Mandatory = $false)]
                    [string]$policyName
                )

                # Configure based on provided parameters
                if ($scopeId -and $policyName) {
                    # Scope and Policy specific configuration
                    Set-DhcpServerv4OptionValue -ScopeId $scopeId -PolicyName $policyName -DnsServer $dnsServer
                    Write-Host "Updated DHCP server with DNS servers: $($dnsServer -join ', ') for scope: $scopeId and policy: $policyName"
                }
                elseif ($scopeId) {
                    # Scope specific configuration
                    Set-DhcpServerv4OptionValue -ScopeId $scopeId -DnsServer $dnsServer
                    Write-Host "Updated DHCP server with DNS servers: $($dnsServer -join ', ') for scope: $scopeId"
                }
                elseif ($policyName) {
                    # Policy specific configuration
                    Set-DhcpServerv4OptionValue -PolicyName $policyName -DnsServer $dnsServer
                    Write-Host "Updated DHCP server with DNS servers: $($dnsServer -join ', ') for policy: $policyName"
                }
                else {
                    # Server-wide configuration
                    Set-DhcpServerv4OptionValue -DnsServer $dnsServer
                    Write-Host "Updated DHCP server with DNS servers: $($dnsServer -join ', ')"
                }
            } -ArgumentList $dnsServer, $data['dhcpScopeId'], $data['dhcpPolicyName']
        }
        catch {
            throw "Failed to update DHCP settings on server $server : $_"
        }
        finally {
            if ($session) {
                Remove-PSSession -Session $session
            }
        }
    }
}
#endregion

# Export all functions
Export-ModuleMember -Function *
param(
    [Parameter(Mandatory = $false)]
    [ValidateScript({
            $fileInfo = New-Object System.IO.FileInfo($_)
            $fileInfo.Exists -and $fileInfo.Directory.Exists
        })]
    [string]$ConfigPath = "./main.psd1",

    [Parameter(Mandatory = $false)]
    [ValidateScript({
            $fileInfo = New-Object System.IO.FileInfo($_)
            $fileInfo.Exists -and $fileInfo.Directory.Exists
        })]
    [string]$InventoryPath = "./inventory.ini",

    [Parameter(Mandatory = $false)]
    [ValidateScript({
            $fileInfo = New-Object System.IO.FileInfo($_)
            $fileInfo.Exists -and $fileInfo.Directory.Exists
        })]
    [string]$TempPath = "./temp",

    [Parameter(Mandatory = $false)]
    # become method for ansible: https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_privilege_escalation.html
    [string]$become = "ask-become-pass"
)

Import-Module ./main.psm1

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
# install pwsh, docker on the remote host and get hosts information
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

# get host information from ansible
[Array]$servers = Get-Content -Path "$TempPath/host_info.csv"
# cleanup
Remove-Item -Path $TempPath -Recurse -Force

# store the needed functions from the module in variables to send them to the remote host
$functions = @("Deploy-Container", "Deploy-Pihole", "Deploy-Unbound", "Deploy-Cloudflared", "Set-PiholeConfiguration", "Invoke-CommandWithCheck")
$functionsDefinitions = Get-FunctionDefinitions -functions $functions

# deploy the stack on each host
# deploying itself could be done trough ansible, but we will use PowerShell to make further changes
foreach ($server in $servers) {
    # make an ssh connection to the remote host
    [string]$hostname, $username = $server -split ','
    $session = New-PSSession -HostName $hostname -UserName $username -SSHTransport
    
    # get the data from the .psd1 file
    [hashtable]$data = Get-Data -ConfigPath $ConfigPath
    
    # deploy the stack on the remote host
    Invoke-Command -Session $session -ScriptBlock {
        param([Parameter(Mandatory = $true)]        
            [hashtable]$data,
            [Parameter(Mandatory = $true)]
            [array]$functionDefinitions)
        # recreate the functions on the remote host
        foreach ($functionDef in $functionDefinitions) {
            . ([ScriptBlock]::Create($functionDef))
        }

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

        # config
        Set-PiholeConfiguration -data $data
    } -ArgumentList $data, $functionsDefinitions
    
    # cleanup
    Remove-PSSession -Session $session
}
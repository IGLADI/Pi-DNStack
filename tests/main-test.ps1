# this test script is ment to be launched from the root directory trough CI/CD

param(
    [string]$password,
    [string]$configDir = "./tests/configs",
    [string]$scriptPath = "./main.ps1",
    [string]$InventoryPath = "./tests/inventory.ini",
    # become sudo for ansible through GitHub secrets
    [string]$become = "extra-vars 'ansible_become_password=$password'"
)

# removes all containers with the stack name
function CleanUpContainers {
    param(
        $session,
        [string]$path
    )

    $config = Import-PowerShellDataFile -Path $path
    [string]$stackName = if ($config.stackName) { $config.stackName } else { 'auto_deployed' }

    Invoke-Command -Session $session -ScriptBlock {
        param([string]$stackName)
        [string]$command = "docker ps -a --filter name=$stackName -q"
        [string[]]$containers = Invoke-Expression $command

        if ($containers) {
            $containers | ForEach-Object {
                docker rm -f $_
            }
        }
    } -ArgumentList $stackName
}

# get host and username from inventory file
[string[]]$servers = Get-Content $InventoryPath
[string]$server = $servers[-1]
[string]$hostname, [string]$username = $server -split ' '
$username = $username -replace "ansible_user=", ""

$session = New-PSSession -HostName $hostname -UserName $username -SSHTransport


# pester tests
Describe "Docker Container Tests" {
    Context "Default Configuration" {
        BeforeAll {
            # run the main script
            pwsh -File $scriptPath -ConfigPath "$configDir/default.psd1" -InventoryPath $InventoryPath -become $become
        }

        It "Should ensure the pihole container is running correctly" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker ps --filter "name=auto_deployed_pihole" --format "{{.Names}}"
            }
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should ensure the pihole container is bound to port 80 and 53" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect auto_deployed_pihole --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}'
            }
            $result | Should -Match "80"
            $result | Should -Match "53"
        }

        It "Should ensure the pihole container has the correct mount for /etc/pihole" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect auto_deployed_pihole --format '{{range .Mounts}}{{.Source}}{{end}}'
            }
            $result | Should -Match "/etc/pihole"
        }

        It "Should ensure the restart policy is set to 'unless-stopped'" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect auto_deployed_pihole --format '{{.HostConfig.RestartPolicy.Name}}'
            }
            $result | Should -Match "unless-stopped"
        }

        It "Should ensure the container network is set to 'bridge'" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect auto_deployed_pihole --format '{{.HostConfig.NetworkMode}}'
            }
            $result | Should -Match "bridge"
        }

        It "Should ensure the unbound container is running correctly" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker ps --filter "name=auto_deployed_pihole" --format "{{.Names}}"
            }
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should ensure the cloudflared container is running correctly" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker ps --filter "name=auto_deployed_cloudflared" --format "{{.Names}}"
            }
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should ensure the pihole container is resolving correctly" {
            [string]$server = Invoke-Command -Session $session -ScriptBlock { 
                docker inspect auto_deployed_pihole --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
            }
            [string]$result = Invoke-Command -Session $session -ScriptBlock { 
                nslookup google.com $server
            } -ArgumentList $server
            $result | Should -Match "Non-authoritative answer"
        }
    }

    Context "Unbound Disabled" {
        BeforeAll {
            # run the main script
            pwsh -File $scriptPath -ConfigPath "$configDir/unbound_disabled.psd1" -InventoryPath $InventoryPath -become $become
        }

        It "Should ensure the unbound container is not running" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker ps --filter "name=auto_deployed_unbound" --format "{{.Names}}" | wc -l
            }
            $result | Should -Be "0"
        }

        It "Should ensure the cloudflared container is still running correctly" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker ps --filter "name=auto_deployed_cloudflared" --format "{{.Names}}"
            }
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should ensure the pihole container is still running correctly" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker ps --filter "name=auto_deployed_pihole" --format "{{.Names}}"
            }
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should ensure the pihole container is resolving correctly" {
            [string]$server = Invoke-Command -Session $session -ScriptBlock { 
                docker inspect auto_deployed_pihole --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
            }
            [string]$result = Invoke-Command -Session $session -ScriptBlock { 
                nslookup google.com $server
            } -ArgumentList $server
            $result | Should -Match "Non-authoritative answer"
        }
    }

    Context "Cloudflared Disabled" {
        BeforeAll {
            # run the main script
            pwsh -File $scriptPath -ConfigPath "$configDir/cloudflared_disabled.psd1" -InventoryPath $InventoryPath -become $become
        }
        It "Should ensure the cloudflared container is not running" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker ps --filter "name=auto_deployed_cloudflared" --format "{{.Names}}" | wc -l
            }
            $result | Should -Be "0"
        }

        It "Should ensure the unbound container is still running correctly" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker ps --filter "name=auto_deployed_unbound" --format "{{.Names}}"
            }
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should ensure the pihole container is still running correctly" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker ps --filter "name=auto_deployed_pihole" --format "{{.Names}}"
            }
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should ensure the pihole container is resolving correctly" {
            [string]$server = Invoke-Command -Session $session -ScriptBlock { 
                docker inspect auto_deployed_pihole --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
            }
            [string]$result = Invoke-Command -Session $session -ScriptBlock { 
                nslookup google.com $server
            } -ArgumentList $server
            $result | Should -Match "Non-authoritative answer"
        }
    }

    Context "StackName Changed" {
        BeforeAll {
            # run the main script
            pwsh -File $scriptPath -ConfigPath "$configDir/stackName_changed.psd1" -InventoryPath $InventoryPath -become $become
        }
        It "Should ensure the stack name is set to 'custom_stack'" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker ps | grep "custom_stack"
            }
            $result | Should -Not -BeNullOrEmpty
        }

        # remove the containers after the context
        AfterAll {
            CleanUpContainers -session $session "$configDir/stackName_changed.psd1"
        }
    }

    Context "Multiple Changes" {
        BeforeAll {
            # run the main script
            pwsh -File $scriptPath -ConfigPath "$configDir/changes.psd1" -InventoryPath $InventoryPath -become $become
        }
        It "Should ensure the restart policy is set to 'always'" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect auto_deployed_pihole --format '{{.HostConfig.RestartPolicy.Name}}'
            }
            $result | Should -Match "always"
        }

        It "Should ensure the Pi-hole container is bound to port 8081 and 5356" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect auto_deployed_pihole --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}'
            }
            $result | Should -Match "8081"
            $result | Should -Match "5356"
        }

        It "Should ensure the unbound container is bound to port 5353" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect auto_deployed_unbound --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}'
            }
            $result | Should -Match "5353"
        }

        It "Should ensure the cloudflared container is bound to port 5054" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect auto_deployed_cloudflared --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}'
            }
            $result | Should -Match "5054"
        }

        It "Should ensure the Pi-hole password is changed" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect auto_deployed_pihole --format '{{range .Config.Env}}{{println .}}{{end}}'
            }
            $result | Should -Match "WEBPASSWORD=secret"
        }
    }

    Context "Host Network" {
        BeforeAll {
            # run the main script
            pwsh -File $scriptPath -ConfigPath "$configDir/host_network.psd1" -InventoryPath $InventoryPath -become $become
        }
        It "Should ensure the container network is set to 'host'" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect auto_deployed_pihole --format '{{.HostConfig.NetworkMode}}'
            }
            $result | Should -Match "host"
        }
    }

    Context "Empty Ports" {
        BeforeAll {
            # run the main script
            pwsh -File $scriptPath -ConfigPath "$configDir/empty_ports.psd1" -InventoryPath $InventoryPath -become $become
        }
        It "Should ensure the pihole container has no ports bound" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect auto_deployed_pihole --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}'
            }
            $result | Should -BeNullOrEmpty
        }

        It "Should ensure the unbound container has no ports bound" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect auto_deployed_unbound --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}'
            }
            $result | Should -BeNullOrEmpty
        }

        It "Should ensure the cloudflared container has no ports bound" {
            [string]$result = Invoke-Command -Session $session -ScriptBlock {
                docker inspect auto_deployed_cloudflared --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}'
            }
            $result | Should -BeNullOrEmpty
        }

        # remove the containers after the last context
        AfterAll {
            CleanUpContainers -session $session "$configDir/empty_ports.psd1"
        }
    }
}

# cleanup
Remove-PSSession $session

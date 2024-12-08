# this test script is ment to be launched from the root directory trough CI/CD

param(
    [string]$password
)

$configDir = "./tests/configs"
$scriptPath = "./main.ps1"
$InventoryPath = "./tests/inventory.ini"
$become = "extra-vars 'ansible_become_password=$password'"

$testCases = @(
    @{
        Name         = "Default"
        ConfigPath   = "$configDir/default.psd1"
        TestCommands = @(
            # with help of https://chatgpt.com/share/67559dde-14f4-8011-92ad-a50ad047b36b
            {
                # check that the pihole container is running correctly
                docker ps --filter "name=auto_deployed_pihole" --format "{{.Names}}"
            },
            {
                # check that the pihole container is bound to the correct port (80)
                docker inspect auto_deployed_pihole --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}' | grep "80"
            },
            {
                # check that the pihole container has the correct mount for /etc/pihole
                docker inspect auto_deployed_pihole --format '{{range .Mounts}}{{.Source}}{{end}}' | grep "/etc/pihole"
            },
            {
                # check that the restart policy is correctly set to "unless-stopped"
                docker inspect auto_deployed_pihole --format '{{.HostConfig.RestartPolicy.Name}}' | grep "unless-stopped"
            },
            {
                # check that the stack name is set to "auto_deployed"
                docker inspect auto_deployed_pihole --format '{{.Config.Labels.com.docker.stack.namespace}}' | grep "auto_deployed"
            },
            {
                # check that the container network is set to "bridge"
                docker inspect auto_deployed_pihole --format '{{.HostConfig.NetworkMode}}' | grep "bridge"
            },
            {
                # check that the Pi-hole image is correct
                docker inspect auto_deployed_pihole --format '{{.Config.Image}}' | grep "pihole/pihole:latest"
            },
            {
                # check that the unbound container is running correctly
                docker ps --filter "name=auto_deployed_unbound" --format "{{.Names}}"
            },
            {
                # check that the unbound container has the correct mount for /etc/unbound
                docker inspect auto_deployed_unbound --format '{{range .Mounts}}{{.Source}}{{end}}' | grep "/etc/unbound"
            },
            {
                # check that the unbound image is correct
                docker inspect auto_deployed_unbound --format '{{.Config.Image}}' | grep "mvance/unbound:latest"
            },
            {
                # check that the cloudflared container is running correctly
                docker ps --filter "name=auto_deployed_cloudflared" --format "{{.Names}}"
            },
            {
                # check that the cloudflared container is bound to the correct port (5053)
                docker inspect auto_deployed_cloudflared --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}' | grep "5053"
            },
            {
                # check that the cloudflared container has the correct mount for /etc/cloudflared
                docker inspect auto_deployed_cloudflared --format '{{range .Mounts}}{{.Source}}{{end}}' | grep "/etc/cloudflared"
            },
            {
                # check that the cloudflared image is correct
                docker inspect auto_deployed_cloudflared --format '{{.Config.Image}}' | grep "cloudflare/cloudflared:latest"
            },
            {
                # check that the unbound configuration file is mounted correctly
                docker inspect auto_deployed_unbound --format '{{range .Mounts}}{{if eq .Destination "/etc/unbound/unbound.conf"}}{{.Source}}{{end}}{{end}}' | grep "/etc/unbound/unbound.conf"
            },
            {
                # check that cloudflared configuration file is mounted correctly
                docker inspect auto_deployed_cloudflared --format '{{range .Mounts}}{{if eq .Destination "/etc/cloudflared/config.yml"}}{{.Source}}{{end}}{{end}}' | grep "/etc/cloudflared/config.yml"
            }
        )
    },
    @{
        Name         = "Unbound Disabled"
        ConfigPath   = "$configDir/unbound_disabled.psd1"
        TestCommands = @(
            {
                # check that the unbound container is not running
                docker ps --filter "name=auto_deployed_unbound" --format "{{.Names}}" | wc -l | grep -q '^0$' && Write-Output "container is not running" || Write-Output "Error"
            },
            {
                # check that the unbound container is still running correctly
                docker ps --filter "name=auto_deployed_unbound" --format "{{.Names}}"
            }
            {
                # check that the pihole container is still running correctly
                docker ps --filter "name=auto_deployed_pihole" --format "{{.Names}}"
            }
        )
    },
    @{
        Name         = "Cloudflared Disabled"
        ConfigPath   = "$configDir/cloudflared_disabled.psd1"
        TestCommands = @(
            {
                # check that the cloudflared container is not running
                docker ps --filter "name=auto_deployed_cloudflared" --format "{{.Names}}" | wc -l | grep -q '^0$' && Write-Output "container is not running" || Write-Output "Error"
            },
            {
                # check that the cloudflared container is still running correctly
                docker ps --filter "name=auto_deployed_cloudflared" --format "{{.Names}}"
            },
            {
                # check that the unbound container is still running correctly
                docker ps --filter "name=auto_deployed_unbound" --format "{{.Names}}"
            },
            {
                # check that the pihole container is still running correctly
                docker ps --filter "name=auto_deployed_pihole" --format "{{.Names}}"
            }
        )
    },
    # with help of https://chatgpt.com/share/67559dcb-6f98-8011-8b79-3e33b53092bf
    @{
        Name         = "RestartPolicy Changed"
        ConfigPath   = "$configDir/restartPolicy_changed.psd1"
        TestCommands = @(
            {
                # check that the restart policy is correctly set to "always"
                docker inspect auto_deployed_pihole --format '{{.HostConfig.RestartPolicy.Name}}' | grep "always"
            }
        )
    },
    @{
        Name         = "StackName Changed"
        ConfigPath   = "$configDir/stackName_changed.psd1"
        TestCommands = @(
            {
                # check that the stack name is set to "custom_stack"
                docker inspect custom_stack_pihole --format '{{.Config.Labels.com.docker.stack.namespace}}' | grep "custom_stack"
            }
        )
    },
    @{
        Name         = "ContainerNetwork Changed"
        ConfigPath   = "$configDir/containerNetwork_changed.psd1"
        TestCommands = @(
            {
                # check that the container network is set to "host"
                docker inspect auto_deployed_pihole --format '{{.HostConfig.NetworkMode}}' | grep "host"
            }
        )
    },
    @{
        Name         = "PiHolePort Changed"
        ConfigPath   = "$configDir/piholePort_changed.psd1"
        TestCommands = @(
            {
                # check that the Pi-hole container is bound to the correct port (8081)
                docker inspect auto_deployed_pihole --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}' | grep "8081"
            }
        )
    },
    @{
        Name         = "PiHolePassword Changed"
        ConfigPath   = "$configDir/piholePassword_changed.psd1"
        TestCommands = @(
            {
                # check that the Pi-hole password is changed
                docker inspect auto_deployed_pihole --format '{{range .Config.Env}}{{if eq . "WEBPASSWORD=secret"}}{{.}}{{end}}{{end}}' | grep "WEBPASSWORD=secret"
            }
        )
    },
    @{
        Name         = "UnboundPort Changed"
        ConfigPath   = "$configDir/unboundPort_changed.psd1"
        TestCommands = @(
            {
                # check that the unbound container is bound to the correct port (5353)
                docker inspect auto_deployed_unbound --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}' | grep "5353"
            }
        )
    },
    @{
        Name         = "CloudflaredPort Changed"
        ConfigPath   = "$configDir/cloudflaredPort_changed.psd1"
        TestCommands = @(
            {
                # check that the cloudflared container is bound to the correct port (5054)
                docker inspect auto_deployed_cloudflared --format '{{range .HostConfig.PortBindings}}{{.}}{{end}}' | grep "5054"
            }
        )
    },
    @{
        Name         = "CloudflaredConfig Changed"
        ConfigPath   = "$configDir/cloudflaredConfig_changed.psd1"
        TestCommands = @(
            {
                # check that the cloudflared configuration file is mounted correctly with a new path
                docker inspect auto_deployed_cloudflared --format '{{range .Mounts}}{{if eq .Destination "/etc/cloudflared/custom_config.yml"}}{{.Source}}{{end}}{{end}}' | grep "/etc/cloudflared/custom_config.yml"
            }
        )
    }
)

function CleanUp {
    param(
        $session
    )

    $config = Import-PowerShellDataFile -Path $test.ConfigPath
    $stackName = if ($config.stackName) { $config.stackName } else { 'auto_deployed' }

    Invoke-Command -Session $session -ScriptBlock {
        param($stackName)
        $command = "docker ps -a --filter name=$stackName -q"
        $containers = Invoke-Expression $command

        if ($containers) {
            $containers | ForEach-Object {
                docker rm -f $_
            }
        }
    } -ArgumentList $stackName
    
}

$servers = Get-Content $InventoryPath
$server = $servers[-1]
[string]$hostname, $username = $server -split ' '
$username = $username -replace "ansible_user=", ""

$session = New-PSSession -HostName $hostname -UserName $username -SSHTransport

$passed = $true
foreach ($test in $testCases) {
    Write-Host "Running test: $($test.Name)"

    CleanUp -session $session

    pwsh -File $scriptPath -ConfigPath $test.ConfigPath -InventoryPath $InventoryPath -become $become

    $testPassed = $true

    foreach ($command in $test.TestCommands) {
        try {
            $result = Invoke-Command -Session $session -ScriptBlock {
                param($command)
                $result = Invoke-Expression $command
                return $result
            } -ArgumentList $command

            if ($result -match "Error") {
                $testPassed = $false
                Write-Error "Test '$($test.Name)' failed at command: $command"
                break
            }
        }
        catch {
            $testPassed = $false
            Write-Error "Test '$($test.Name)' crashed at command: $command"
            break
        }
    }

    if ($testPassed) {
        Write-Host "Test '$($test.Name)' passed!" -ForegroundColor Green
    }
    else {
        Write-Error "Test '$($test.Name)' failed."
        # continue instead so that all tests are run and we can see all failures at once
        $passed = $false
    }

}

CleanUp -session $session
Remove-PSSession -Session $session

if ($passed) {
    Write-Host "All tests passed!" -ForegroundColor Green
}
else {
    Write-Error "Some tests failed."
    exit 1
}

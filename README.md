<!-- Disclaimer: Readme had been refined by ai -->

# Pi-DNStack

## Overview

Pi-DNStack is an automated solution for deploying a containerized DNS management stack, including:

-   [**Pi-hole**](https://pi-hole.net): Network-wide ad blocking and DNS management
-   [**Unbound**](https://docs.pi-hole.net/guides/dns/unbound/): Local recursive DNS resolver
-   [**Cloudflared**](https://docs.pi-hole.net/guides/dns/cloudflared/): DNS-over-HTTPS (DoH) proxy

## Features

-   Automated Preconfigured Deployment
-   Declarative (and idempotent) Configuration: Compares your .psd1 with the current state and only applies necessary changes
-   Multi-host deployment support
-   Automatic dependency installation
-   Optional Windows DHCP configuration

## Prerequisites

### System Requirements

-   **Target Server(s)**:

    -   Linux-based operating system
        -   Debian-based: Ubuntu, Raspbian, etc.
        -   RPM-based: Fedora, CentOS, RHEL, SUSE, etc.
        -   Other distributions if dependencies are pre-installed
    -   Sufficient privileges

-   **Management Workstation**:
    -   PowerShell 7+
    -   SSH access to the target server(s) through [public key authentication](https://www.digitalocean.com/community/tutorials/how-to-configure-ssh-key-based-authentication-on-a-linux-server)
    -   Supported platforms:
        -   Linux Workstation (Physical or Virtual)
            -   Debian-based: using `apt`
            -   RedHat-based: using `dnf`
            -   Arch-based: using `pacman`
            -   Other distributions if dependencies are pre-installed
        -   Windows users can use [WSL2](https://docs.microsoft.com/en-us/windows/wsl/install)

> [!WARNING]
> All deployment steps below should be run from your **workstation**, not directly on the target server.  
> The script connects to the servers via SSH.  
> You _can_ use the server as its own workstation if it has PowerShell 7 and SSH access to itself, but that's not the main use case.

## Quick Start

1.  **Clone Repository**

    ```bash
    git clone https://github.com/IGLADI/Pi-DNStack && cd Pi-DNStack
    ```

2.  **Configure Target Hosts**

    Create an inventory file ([`inventory.ini`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/ini_inventory.html)) listing your target servers:

    ```bash
    nano inventory.ini
    ```

    Example `inventory.ini`:

    ```ini
    192.168.1.10 ansible_user=ansible
    ```

    > [!NOTE]
    > If you have a single server, you can just copy this example and replace the IP address and user.  
    > The specified user must have sudo privileges on the target system.

3.  **Configure Deployment**

    Copy and modify the configuration template:

    ```bash
    cp main.psd1.example main.psd1
    nano main.psd1
    ```

    > [!WARNING]
    > At minimum, change the default Pi-hole password in the configuration file!

4.  **Deploy the Stack**

    ```bash
    pwsh ./main.ps1 -ConfigPath ./main.psd1
    ```

    > [!WARNING]
    > Make sure you run the above command from your **workstation**, not directly on the target server(s).  
    > Please ensure SSH access is properly configured.

5.  **Enjoy!**

    After deployment, access the Pi-hole web interface at: `http://<server-ip>:<port>/admin/login`, [configure your clients](https://www.windowscentral.com/how-change-your-pcs-dns-settings-windows-10#:~:text=HOW%20TO%20CHANGE%20DNS%20SETTINGS%20USING%20SETTINGS%20ON%20WINDOWS%2010) to use Pi-DNStack as DNS server and enjoy your new DNS management stack!

    > [!WARNING]
    > Clients must be able to reach your server on port 53 (DNS).  
    > Firewalls or network rules may block this: [How to open port 53](https://www.cyberciti.biz/faq/howto-open-dns-port-53-using-ufw-ubuntu-debian/)  
    > To confirm it's working, check if your clients show up in the Pi-hole dashboard.

## Windows DHCP Configuration

Pi-DNStack can automatically configure a Windows DHCP server to use Pi-hole. This feature requires:

### Prerequisites

-   Windows Server with DHCP role installed
-   [Powershell SSH remoting access](https://learn.microsoft.com/th-th/powershell/scripting/security/remoting/ssh-remoting-in-powershell?view=powershell-7.4) to the target server(s)
-   Network connectivity between:
    -   Windows DHCP server and Pi-hole server
    -   Management workstation and Windows DHCP server

### Network Considerations

1. **Docker Network Mode**:

    - If using `bridge` mode, ensure Pi-hole's DNS port is published (`piholeDnsPort = "53"`)
    - If using `host` mode (recommended when using this feature), ensure the host's firewall allows DNS traffic and unbound is disabled (both containers would use port 53)

2. **Pi-hole Listen Configuration**:
    - Ensure Pi-hole is configured to listen to the required interfaces.

### Configuration

To enable DHCP integration, edit the `#region DHCP Configuration` section in your `main.psd1` file. The configuration file contains detailed comments and examples for all available DHCP options.

## Troubleshooting

-   Check the log file at `~/log/pi-dnstack/main.log` for detailed deployment information
-   Verify network connectivity and port availability on target hosts
-   For unresolved issues, please check [GitHub Issues](https://github.com/IGLADI/Pi-DNStack/issues)

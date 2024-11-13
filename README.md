# Pi-DNStack

## Project Description

Pi-DNStack automates the deployment of a containerized DNS stack. This project will deploy and configure [Pi-hole](https://docs.pi-hole.net) for blocking unwanted traffic, while utilizing [Unbound](https://unbound.docs.nlnetlabs.nl/en/latest/) and [Cloudflared](https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/) as upstream DNS servers. This stack provides both DNS filtering and local DNS entry management while improving privacy and security.

## Requirements

-   [PowerShell](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell?view=powershell-7.4)
-   A Linux Server with SSH access (Debian and RedHat based distributions are supported, other distributions may require additional configuration)

## Quick start

Clone this repository

```bash
git clone git@github.com:IGLADI/Pi-DNStack.git && cd Pi-DNStack
```

Create an [`inventory.ini` file](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/ini_inventory.html)) that contains the list of hosts where you want to deploy this stack and the user (we recommend using a dedicated used with [SSH key pairs](https://help.ubuntu.com/community/SSH/OpenSSH/Keys)) that will be used by this script.

```bash
nano inventory.ini
```

Example inventory.ini:

```ini
192.168.1.10 ansible_user=ansible
```

Run the script

```bash
pwsh main.ps1
```

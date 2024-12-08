@{
    # restartPolicy      = "unless-stopped"
    # stackName          = "auto_deployed"
    # containerNetwork   = "bridge"

    # piholeImage        = "pihole/pihole:latest"
    # piholePort         = "80"
    # # ! change the password !
    # piholePassword     = "admin"

    # unboundEnabled     = $true
    # unboundImage       = "mvance/unbound:latest"
    # unboundPort        = "53"
    # unboundConfig      = "/etc/unbound/unbound.conf"

    # cloudflaredEnabled = $true
    # cloudflaredImage   = "cloudflare/cloudflared:latest"
    # cloudflaredPort    = "5053"
    # cloudflaredConfig  = "/etc/cloudflared/config.yml"

    # piholeVolumes      = [array]@("/etc/pihole:/etc/pihole", "/etc-dnsmasq.d:/etc/dnsmasq.d")
    # unboundVolumes     = [array]@("/etc/unbound:/etc/unbound")
    # cloudflaredVolumes = [array]@("/etc/cloudflared:/etc/cloudflared")

    # commonFlags        = ""
    # piholeFlags        = ""
    # unboundFlags       = ""
    # cloudflaredFlags   = ""
}
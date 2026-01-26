@{
    restartPolicy      = "unless-stopped"
    stackName          = "Pi-DNStack"
    containerEngine    = "docker"
    containerNetwork   = "bridge"
    piholeImage        = "pihole/pihole:latest"
    piholeUiPort       = "80"
    piholeDnsPort      = "53"
    DNSSECEnabled      = $true
    adlists            = @("https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts",
        "https://adaway.org/hosts.txt",
        "https://v.firebog.net/hosts/AdguardDNS.txt",
        "https://v.firebog.net/hosts/Admiral.txt",
        "https://raw.githubusercontent.com/anudeepND/blacklist/master/adservers.txt",
        "https://v.firebog.net/hosts/Easylist.txt",
        "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext",
        "https://raw.githubusercontent.com/FadeMind/hosts.extras/master/UncheckyAds/hosts",
        "https://raw.githubusercontent.com/bigdargon/hostsVN/master/hosts",
        "https://v.firebog.net/hosts/Easyprivacy.txt",
        "https://v.firebog.net/hosts/Prigent-Ads.txt",
        "https://raw.githubusercontent.com/FadeMind/hosts.extras/master/add.2o7Net/hosts",
        "https://raw.githubusercontent.com/crazy-max/WindowsSpyBlocker/master/data/hosts/spy.txt",
        "https://hostfiles.frogeye.fr/firstparty-trackers-hosts.txt",
        "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/Alternate%20versions%20Anti-Malware%20List/AntiMalwareHosts.txt",
        "https://osint.digitalside.it/Threat-Intel/lists/latestdomains.txt",
        "https://v.firebog.net/hosts/Prigent-Crypto.txt",
        "https://raw.githubusercontent.com/FadeMind/hosts.extras/master/add.Risk/hosts",
        "https://bitbucket.org/ethanr/dns-blacklists/raw/8575c9f96e5b4a1308f2f12394abd86d0927a4a0/bad_lists/Mandiant_APT1_Report_Appendix_D.txt",
        "https://phishing.army/download/phishing_army_blocklist_extended.txt",
        "https://gitlab.com/quidsup/notrack-blocklists/raw/master/notrack-malware.txt",
        "https://v.firebog.net/hosts/RPiList-Malware.txt",
        "https://v.firebog.net/hosts/RPiList-Phishing.txt",
        "https://raw.githubusercontent.com/Spam404/lists/master/main-blacklist.txt",
        "https://raw.githubusercontent.com/AssoEchap/stalkerware-indicators/master/generated/hosts",
        "https://urlhaus.abuse.ch/downloads/hostfile/",
        "https://zerodot1.gitlab.io/CoinBlockerLists/hosts_browser",
        "https://raw.githubusercontent.com/PolishFiltersTeam/KADhosts/master/KADhosts.txt",
        "https://raw.githubusercontent.com/FadeMind/hosts.extras/master/add.Spam/hosts",
        "https://v.firebog.net/hosts/static/w3kbl.txt")
    listen             = ""
    interface          = ""
    piholePassword     = "CI-test"
    extraDNS           = @()
    unboundEnabled     = $false
    unboundImage       = "mvance/unbound:latest"
    unboundArmImage    = "mvance/unbound-rpi"
    unboundPort        = "54"
    cloudflaredEnabled = $true
    cloudflaredImage   = "cloudflare/cloudflared:latest"
    cloudflaredPort    = ""
    piholeVolumes      = @("/etc/pihole:/etc/pihole", "/etc-dnsmasq.d:/etc/dnsmasq.d")
    commonFlags        = ""
    piholeFlags        = ""
    unboundFlags       = ""
    cloudflaredFlags   = ""
    forceRedeploy      = $false
    logFile            = "~/.pi-dnstack.log"
}
# Vaultwarden Install (Docker + Nginx Proxy Manager + nightly backups)

All the commands from the video, in the same order. Copy and paste along with me.

Tested on: Debian 12 LXC on Proxmox, Docker 29, Vaultwarden 1.37.

**Change these to match your setup:**
| In the video | Yours |
|---|---|
| `vault.itera.ca` | your domain, e.g. `vault.example.com` |
| `10.37.0.40` | IP of your Vaultwarden machine/container |
| `10.37.0.29` | IP of your Nginx Proxy Manager |

## What you need
- A Debian or Ubuntu machine, VM or LXC container you can SSH into (1 core / 512 MB RAM is plenty)
- A reverse proxy with an SSL certificate. Vaultwarden **only works over HTTPS**. I use Nginx Proxy Manager with a wildcard cert (`*.itera.ca`).
- A local DNS server (Pi-hole, pfSense, your router...) to point your domain at the proxy

> Proxmox LXC users: the container needs **nesting** and **keyctl** enabled (Options → Features) for Docker to work.

---

## 1. SSH in and update
```bash
ssh root@10.37.0.40
apt update && apt upgrade -y
```
> Not logged in as root? Put `sudo` in front of the commands.

## 2. Install Docker
Official steps from https://docs.docker.com/engine/install/debian/
```bash
apt install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
```
```bash
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
```
<details>
<summary><b>On Ubuntu instead of Debian?</b> Use these two commands instead (click)</summary>

```bash
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" > /etc/apt/sources.list.d/docker.list
```
</details>

```bash
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl status docker --no-pager
docker run --rm hello-world
```
You should see **Hello from Docker!**

## 3. Vaultwarden compose file
```bash
mkdir -p /opt/vaultwarden && cd /opt/vaultwarden
nano docker-compose.yml
```
Paste this (change the domain to yours):
```yaml
services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: unless-stopped
    environment:
      DOMAIN: "https://vault.itera.ca"
      SIGNUPS_ALLOWED: "true"
    volumes:
      - ./vw-data:/data
    ports:
      - "8080:80"
```
Save: `Ctrl+O`, `Enter`, exit: `Ctrl+X`

Or download it instead of typing it (then edit the domain with `nano docker-compose.yml`):
```bash
curl -fsSLO https://raw.githubusercontent.com/wetsand24/Vaultwarden_Install/main/docker-compose.yml
```
> YAML is picky: use spaces, not tabs, and keep the indentation exactly like above.

## 4. Start Vaultwarden
```bash
cat docker-compose.yml
docker compose up -d
docker ps
```
`health: starting` is normal for the first few seconds.

## 5. Local DNS record (Pi-hole)
**Settings → Local DNS Records**
- Domain: `vault.itera.ca`
- IP: **your Nginx Proxy Manager IP** (`10.37.0.29`), not the Vaultwarden IP

Using pfSense / your router? Add the same host override there.

## 6. Nginx Proxy Manager
**Hosts → Proxy Hosts → Add Proxy Host**
- Domain Names: `vault.itera.ca`
- Scheme: `http`, Forward Hostname/IP: `10.37.0.40`, Forward Port: `8080`
- Access List: I use my own **Internal Only** list (LAN only). Optional.
- **Websockets Support: on** (NPMplus has it on by default, on regular NPM tick the box)
- TLS / SSL tab: pick your certificate (`*.itera.ca`), turn on **Force HTTPS**
- Save

### Don't have a certificate yet?
In the video I use a wildcard certificate (`*.itera.ca`) I already had. To get your own **free** one from Let's Encrypt in Nginx Proxy Manager:

**Option A: DNS challenge (recommended, no port forwarding)**
NPM proves you own the domain through your DNS provider's API, so nothing has to be open to the internet, and you can get a wildcard cert that covers every service.
1. At your DNS provider, create an API token that can **only edit DNS** for your domain
   (Cloudflare: *My Profile → API Tokens → Create Token → "Edit zone DNS" template → your zone*).
2. NPM → **Certificates → Add Certificate → Let's Encrypt**
3. Domain names: `*.example.com` and `example.com`
4. Turn on **Use a DNS Challenge**, pick your provider, paste the token into the credentials box
   (Cloudflare: `dns_cloudflare_api_token = YOUR_TOKEN`)
5. Agree to the terms → Save. After a minute or two the certificate shows up. Pick it in the proxy host's TLS/SSL tab.

**Option B: HTTP challenge (simpler, but needs port forwarding)**
Let's Encrypt must reach NPM from the internet: forward **port 80** on your router to NPM, and your domain must point to your **public IP**. This exposes NPM to the internet, so for something like a password manager Option A is the better choice.

## 7. Create your account
Open `https://vault.itera.ca` → **Create account** → email, name → master password.
> There is **no way to recover** a lost master password. Write it down somewhere safe.

### Import passwords (optional)
Coming from Bitwarden, LastPass, 1Password or Chrome? Export there, then in Vaultwarden: **Import passwords → File format → pick yours → Choose File → Import**.
Delete the export file afterwards. It contains all your passwords in plain text.

## 8. Turn off signups
```bash
ssh root@10.37.0.40
cd /opt/vaultwarden
nano docker-compose.yml
```
In nano: `Ctrl+W`, type `true`, Enter, change it to `false`. Save and exit.
```bash
grep SIGNUPS docker-compose.yml
docker compose up -d
docker ps
```
Try **Create account** again: you should get *Registration not allowed*.

## 9. Backups
```bash
cd /opt/vaultwarden
nano backup.sh
```
```bash
#!/bin/bash
cd /opt/vaultwarden || exit 1
mkdir -p backups
docker compose stop vaultwarden
tar -czf "backups/vw-data-$(date +%F).tar.gz" vw-data
docker compose start vaultwarden
ls -1t backups/vw-data-*.tar.gz | tail -n +31 | xargs -r rm --
```
Keeps the 30 newest backups. Or download it:
```bash
curl -fsSLO https://raw.githubusercontent.com/wetsand24/Vaultwarden_Install/main/backup.sh
```
```bash
chmod +x backup.sh
./backup.sh
ls -lh backups
docker ps
```

### Run it every night at 3 AM
```bash
crontab -e
```
First time? Pick `1` (nano). Go to the bottom and add:
```
0 3 * * * /opt/vaultwarden/backup.sh
```
Save, exit, then check:
```bash
crontab -l | tail -2
```
> The backups are on the same machine. Copy `/opt/vaultwarden/backups` somewhere else too (NAS, another drive...).

### Restore a backup
```bash
cd /opt/vaultwarden
docker compose stop vaultwarden
mv vw-data vw-data.old
tar -xzf backups/vw-data-YYYY-MM-DD.tar.gz
docker compose start vaultwarden
```

---

## Update Vaultwarden later
```bash
cd /opt/vaultwarden
./backup.sh
docker compose pull && docker compose up -d
```

## Troubleshooting
- **Page loads but you can't create an account / "HTTPS required" error:** you're on `http://` or the IP. Open it through your domain with `https://`.
- **Domain doesn't resolve:** check the DNS record points to the **proxy** IP, and that your PC actually uses that DNS server.
- **502 Bad Gateway in NPM:** wrong forward IP/port, or the container isn't running (`docker ps`).
- **Docker won't start in an LXC:** enable nesting + keyctl on the container in Proxmox.

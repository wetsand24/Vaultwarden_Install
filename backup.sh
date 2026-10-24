#!/bin/bash
cd /opt/vaultwarden || exit 1
mkdir -p backups
docker compose stop vaultwarden
tar -czf "backups/vw-data-$(date +%F).tar.gz" vw-data
docker compose start vaultwarden
ls -1t backups/vw-data-*.tar.gz | tail -n +31 | xargs -r rm --

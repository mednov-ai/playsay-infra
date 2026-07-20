#!/usr/bin/env bash
set -Eeuo pipefail

[[ "${EUID}" -eq 0 ]] || { echo "Run as root on AX41" >&2; exit 1; }

certbot certonly \
  --webroot -w /var/www/playsay-acme \
  --cert-name online.honey.school \
  --non-interactive --agree-tos --register-unsafely-without-email \
  --keep-until-expiring \
  -d online.honey.school \
  -d key.honey.school \
  -d dev.online.honey.school \
  -d dev.key.honey.school

nginx -t
systemctl reload nginx

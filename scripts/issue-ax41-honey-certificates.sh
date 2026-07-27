#!/usr/bin/env bash
set -Eeuo pipefail

[[ "${EUID}" -eq 0 ]] || { echo "Run as root on AX41" >&2; exit 1; }

certbot certonly \
  --webroot -w /var/www/playsay-acme \
  --cert-name online.honey.school \
  --non-interactive --agree-tos --register-unsafely-without-email \
  --keep-until-expiring \
  --expand \
  -d online.honey.school \
  -d key.honey.school \
  -d dev.online.honey.school \
  -d dev.key.honey.school \
  -d ops.honey.school \
  -d dev.ops.honey.school \
  -d jenkins.honey.school \
  -d argocd.ops.honey.school \
  -d argocd.dev.ops.honey.school \
  -d headlamp.ops.honey.school \
  -d headlamp.dev.ops.honey.school \
  -d metrics.dev.ops.honey.school \
  -d jenkins.ops.honey.school \
  -d workflows.ops.honey.school \
  -d workflows.honey.school \
  -d cockpit.ops.honey.school \
  -d hooks.honey.school

nginx -t
systemctl reload nginx

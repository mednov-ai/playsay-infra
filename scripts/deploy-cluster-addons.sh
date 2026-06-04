#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-dev}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DOMAIN="${PLAYSAY_DOMAIN:-dev.playsay.local}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-admin@example.com}"
ARGOCD_HOST="${ARGOCD_HOST:-argocd.$DOMAIN}"
HEADLAMP_HOST="${HEADLAMP_HOST:-headlamp.$DOMAIN}"
OPS_HOST="${OPS_HOST:-ops.$DOMAIN}"
OPS_PORT="${OPS_PORT:-18443}"
OPS_ALLOW_CIDRS="${OPS_ALLOW_CIDRS:-}"
OPS_TLS_MODE="${OPS_TLS_MODE:-auto}"
ONLINE_HOST="${ONLINE_HOST:-online.$DOMAIN}"
ONLINE_NODEPORT_HTTP="${ONLINE_NODEPORT_HTTP:-32083}"
ONLINE_TLS_MODE="${ONLINE_TLS_MODE:-auto}"
COLLABORATION_NODEPORT_HTTP="${COLLABORATION_NODEPORT_HTTP:-32086}"
KEYCLOAK_NODEPORT_HTTP="${KEYCLOAK_NODEPORT_HTTP:-32084}"
LIVEKIT_SIGNALING_HOST_PORT="${LIVEKIT_SIGNALING_HOST_PORT:-7880}"
VICTORIA_METRICS_NODEPORT_HTTP="${VICTORIA_METRICS_NODEPORT_HTTP:-32085}"
INSTALL_JENKINS="${INSTALL_JENKINS:-true}"
JENKINS_NODEPORT_HTTP="${JENKINS_NODEPORT_HTTP:-32082}"
INSTALL_INGRESS_NGINX="${INSTALL_INGRESS_NGINX:-false}"
INSTALL_CERT_MANAGER="${INSTALL_CERT_MANAGER:-false}"
CONFIGURE_HOST_NGINX="${CONFIGURE_HOST_NGINX:-true}"
ARGOCD_NODEPORT_HTTP="${ARGOCD_NODEPORT_HTTP:-32080}"
HEADLAMP_NODEPORT_HTTP="${HEADLAMP_NODEPORT_HTTP:-32081}"
OPS_SCHEME="https"
ONLINE_SCHEME="https"

usage() {
  cat <<USAGE
Usage:
  $0 [environment]

Installs Play&Say cluster add-ons into the active Kubernetes cluster.

Environment variables:
  PLAYSAY_DOMAIN         Base dev domain. Default: dev.playsay.local
  LETSENCRYPT_EMAIL      ACME account email. Default: admin@example.com
  ARGOCD_HOST            ArgoCD host. Default: argocd.<PLAYSAY_DOMAIN>
  HEADLAMP_HOST          Kubernetes UI host. Default: headlamp.<PLAYSAY_DOMAIN>
  OPS_HOST               Shared ops UI host. Default: ops.<PLAYSAY_DOMAIN>
  OPS_PORT               Shared ops UI public port. Default: 18443
  OPS_ALLOW_CIDRS        Optional comma-separated allowlist CIDRs for ops UI
  OPS_TLS_MODE           auto, self-signed, existing, or off. Default: auto
  ONLINE_HOST            Product SPA host. Default: online.<PLAYSAY_DOMAIN>
  ONLINE_NODEPORT_HTTP   Local web-app NodePort. Default: 32083
  ONLINE_TLS_MODE        auto, self-signed, existing, or off. Default: auto
  COLLABORATION_NODEPORT_HTTP Local collaboration-service NodePort for /collab/ws. Default: 32086
  KEYCLOAK_NODEPORT_HTTP Local Keycloak NodePort for /keycloak/. Default: 32084
  LIVEKIT_SIGNALING_HOST_PORT Local LiveKit signaling port for /livekit/. Default: 7880
  VICTORIA_METRICS_NODEPORT_HTTP Local VictoriaMetrics NodePort for /victoria-metrics/. Default: 32085
  INSTALL_JENKINS        Install Jenkins controller. Default: true
  JENKINS_NODEPORT_HTTP  Local Jenkins NodePort. Default: 32082
  INSTALL_INGRESS_NGINX  Install ingress-nginx. Default: false
  INSTALL_CERT_MANAGER   Install cert-manager. Default: false
  CONFIGURE_HOST_NGINX   Add a separate host nginx proxy config. Default: true
  KUBECONFIG             Defaults to /etc/rancher/k3s/k3s.yaml when present
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require() {
  command -v "$1" >/dev/null || { echo "$1 is required" >&2; exit 1; }
}

if ! command -v kubectl >/dev/null && command -v k3s >/dev/null; then
  ln -sf "$(command -v k3s)" /usr/local/bin/kubectl
fi

if ! command -v helm >/dev/null; then
  if [[ "$(uname -s)" == "Linux" && "${EUID:-$(id -u)}" -eq 0 ]] && command -v curl >/dev/null; then
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  else
    echo "helm is missing; install helm first or run this script as root on the VPS" >&2
    exit 1
  fi
fi

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

require kubectl
require helm

kubectl cluster-info >/dev/null

if [[ -x "$ROOT_DIR/scripts/sync-livekit-secret.sh" ]]; then
  "$ROOT_DIR/scripts/sync-livekit-secret.sh"
fi

if [[ -x "$ROOT_DIR/scripts/sync-coturn-secret.sh" ]]; then
  "$ROOT_DIR/scripts/sync-coturn-secret.sh"
fi

if [[ -x "$ROOT_DIR/scripts/sync-object-storage-secret.sh" ]]; then
  "$ROOT_DIR/scripts/sync-object-storage-secret.sh"
fi

if [[ -x "$ROOT_DIR/scripts/sync-collaboration-secret.sh" ]]; then
  "$ROOT_DIR/scripts/sync-collaboration-secret.sh"
fi

if [[ "$INSTALL_INGRESS_NGINX" == "true" ]]; then
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null
fi
if [[ "$INSTALL_CERT_MANAGER" == "true" ]]; then
  helm repo add jetstack https://charts.jetstack.io >/dev/null
fi
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets >/dev/null
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
if [[ "$INSTALL_JENKINS" == "true" ]]; then
  helm repo add jenkins https://charts.jenkins.io >/dev/null
fi
helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/ >/dev/null
helm repo update >/dev/null

if [[ "$INSTALL_INGRESS_NGINX" == "true" ]]; then
  kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -
  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx \
    --set controller.service.type=NodePort \
    --set controller.publishService.enabled=false
fi

if [[ "$INSTALL_CERT_MANAGER" == "true" ]]; then
  kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --set crds.enabled=true

  kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-http01
spec:
  acme:
    email: ${LETSENCRYPT_EMAIL}
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-http01-account-key
    solvers:
      - http01:
          ingress:
            class: nginx
EOF
fi

kubectl create namespace sealed-secrets --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace sealed-secrets

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --set configs.params."server\\.insecure"=true \
  --set configs.params."server\\.basehref"=/argocd \
  --set configs.params."server\\.rootpath"=/argocd \
  --set server.service.type=NodePort \
  --set server.service.nodePortHttp="$ARGOCD_NODEPORT_HTTP" \
  --set server.ingress.enabled=false

kubectl create namespace headlamp --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install headlamp headlamp/headlamp \
  --namespace headlamp \
  --set config.inCluster=true \
  --set config.enableHelm=true \
  --set config.baseURL=/headlamp \
  --set service.type=NodePort \
  --set service.nodePort="$HEADLAMP_NODEPORT_HTTP" \
  --set ingress.enabled=false

kubectl -n headlamp apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: headlamp-admin-token
  annotations:
    kubernetes.io/service-account.name: headlamp
type: kubernetes.io/service-account-token
EOF

if [[ "$INSTALL_JENKINS" == "true" ]]; then
  kubectl create namespace jenkins --dry-run=client -o yaml | kubectl apply -f -
  kubectl create namespace playsay-dev --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n jenkins apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jenkins-agent-cache
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 4Gi
EOF

  kubectl -n argocd apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: jenkins-dev-rollout-reader
rules:
  - apiGroups:
      - argoproj.io
    resources:
      - applications
    verbs:
      - get
      - list
      - patch
      - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: jenkins-dev-rollout-reader
subjects:
  - kind: ServiceAccount
    name: jenkins
    namespace: jenkins
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: jenkins-dev-rollout-reader
EOF

  kubectl -n playsay-dev apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: jenkins-dev-rollout-reader
rules:
  - apiGroups:
      - apps
    resources:
      - deployments
      - replicasets
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - ""
    resources:
      - pods
    verbs:
      - get
      - list
      - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: jenkins-dev-rollout-reader
subjects:
  - kind: ServiceAccount
    name: jenkins
    namespace: jenkins
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: jenkins-dev-rollout-reader
EOF

  helm upgrade --install jenkins jenkins/jenkins \
    --namespace jenkins \
    --set controller.jenkinsUriPrefix=/jenkins \
    --set controller.serviceType=NodePort \
    --set controller.nodePort="$JENKINS_NODEPORT_HTTP" \
    --set controller.servicePort=8080 \
    --set controller.installPlugins[0]=kubernetes \
    --set controller.installPlugins[1]=workflow-aggregator \
    --set controller.installPlugins[2]=git \
    --set controller.installPlugins[3]=github \
    --set controller.installPlugins[4]=github-branch-source \
    --set controller.installPlugins[5]=credentials-binding \
    --set controller.installPlugins[6]=configuration-as-code \
    --set controller.installPlugins[7]=timestamper \
    --set controller.installPlugins[8]=pipeline-stage-view \
    --set controller.installPlugins[9]=generic-webhook-trigger \
    --set controller.overwritePlugins=true \
    --set controller.resources.requests.cpu=250m \
    --set controller.resources.requests.memory=768Mi \
    --set controller.resources.limits.cpu=1500m \
    --set controller.resources.limits.memory=1536Mi \
    --set persistence.enabled=true \
    --set persistence.size=8Gi

  JENKINS_APPLY_CONFIG_TMP="$(mktemp)"
  kubectl -n jenkins get configmap jenkins -o jsonpath='{.data.apply_config\.sh}' > "$JENKINS_APPLY_CONFIG_TMP"
  if grep -q 'yes n | cp -i /usr/share/jenkins/ref/plugins/\* /var/jenkins_plugins/;' "$JENKINS_APPLY_CONFIG_TMP"; then
    sed -i 's#yes n | cp -i /usr/share/jenkins/ref/plugins/\* /var/jenkins_plugins/;#cp -f /usr/share/jenkins/ref/plugins/* /var/jenkins_plugins/;#' "$JENKINS_APPLY_CONFIG_TMP"
    JENKINS_PATCH_TMP="$(mktemp)"
    {
      printf 'data:\n  apply_config.sh: |\n'
      sed 's/^/    /' "$JENKINS_APPLY_CONFIG_TMP"
    } > "$JENKINS_PATCH_TMP"
    kubectl -n jenkins patch configmap jenkins --type merge --patch-file "$JENKINS_PATCH_TMP"
    rm -f "$JENKINS_PATCH_TMP"
  fi
  rm -f "$JENKINS_APPLY_CONFIG_TMP"

  if kubectl -n jenkins get pod jenkins-0 -o jsonpath='{range .status.initContainerStatuses[*]}{.state.waiting.reason}{"\n"}{end}' 2>/dev/null | grep -q '^CrashLoopBackOff$'; then
    kubectl -n jenkins delete pod jenkins-0 --wait=false
  fi

  kubectl -n jenkins rollout status statefulset/jenkins --timeout=600s
  JENKINS_NODEPORT_HTTP="$JENKINS_NODEPORT_HTTP" \
    "$ROOT_DIR/scripts/configure-jenkins-jobs.sh"
fi

if [[ "$CONFIGURE_HOST_NGINX" == "true" ]]; then
  if command -v nginx >/dev/null; then
    OPS_SCHEME="http"
    OPS_LISTEN_DIRECTIVE="listen ${OPS_PORT};"
    OPS_SSL_DIRECTIVES=""

    if [[ "$OPS_TLS_MODE" != "off" ]]; then
      LETSENCRYPT_CERT="/etc/letsencrypt/live/${OPS_HOST}/fullchain.pem"
      LETSENCRYPT_KEY="/etc/letsencrypt/live/${OPS_HOST}/privkey.pem"
      SELF_SIGNED_DIR="/etc/nginx/playsay-ops"
      SELF_SIGNED_CERT="${SELF_SIGNED_DIR}/${OPS_HOST}.crt"
      SELF_SIGNED_KEY="${SELF_SIGNED_DIR}/${OPS_HOST}.key"

      if [[ -f "$LETSENCRYPT_CERT" && -f "$LETSENCRYPT_KEY" ]]; then
        OPS_SCHEME="https"
        OPS_LISTEN_DIRECTIVE="listen ${OPS_PORT} ssl;"
        OPS_SSL_DIRECTIVES="    ssl_certificate ${LETSENCRYPT_CERT};
    ssl_certificate_key ${LETSENCRYPT_KEY};
"
      elif [[ "$OPS_TLS_MODE" == "existing" ]]; then
        echo "OPS_TLS_MODE=existing but certificate is missing for ${OPS_HOST}" >&2
        exit 1
      else
        mkdir -p "$SELF_SIGNED_DIR"
        chmod 700 "$SELF_SIGNED_DIR"
        if [[ ! -f "$SELF_SIGNED_CERT" || ! -f "$SELF_SIGNED_KEY" ]]; then
          openssl req -x509 -nodes -newkey rsa:2048 \
            -keyout "$SELF_SIGNED_KEY" \
            -out "$SELF_SIGNED_CERT" \
            -days 365 \
            -subj "/CN=${OPS_HOST}" \
            -addext "subjectAltName=DNS:${OPS_HOST}"
          chmod 600 "$SELF_SIGNED_KEY"
        fi
        OPS_SCHEME="https"
        OPS_LISTEN_DIRECTIVE="listen ${OPS_PORT} ssl;"
        OPS_SSL_DIRECTIVES="    ssl_certificate ${SELF_SIGNED_CERT};
    ssl_certificate_key ${SELF_SIGNED_KEY};
"
      fi
    fi

    OPS_ALLOW_DIRECTIVES=""
    if [[ -n "$OPS_ALLOW_CIDRS" ]]; then
      IFS=',' read -r -a OPS_ALLOW_LIST <<< "$OPS_ALLOW_CIDRS"
      for cidr in "${OPS_ALLOW_LIST[@]}"; do
        OPS_ALLOW_DIRECTIVES="${OPS_ALLOW_DIRECTIVES}    allow ${cidr};
"
      done
      OPS_ALLOW_DIRECTIVES="${OPS_ALLOW_DIRECTIVES}    deny all;
"
    fi

    ONLINE_HTTP_SERVER=""
    ONLINE_HTTPS_SERVER=""
    ONLINE_LIVEKIT_LOCATION="    location /livekit/ {
        proxy_pass http://127.0.0.1:${LIVEKIT_SIGNALING_HOST_PORT}/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \"upgrade\";
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location = /livekit {
        return 301 /livekit/;
    }
"
    ONLINE_COLLABORATION_LOCATION="    location = /collab/ws {
        proxy_pass http://127.0.0.1:${COLLABORATION_NODEPORT_HTTP};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \"upgrade\";
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
"
    ONLINE_VIDEO_RELAY_LOCATION="    location ^~ /api/materials/video-playback-sessions/ {
        proxy_pass http://127.0.0.1:${ONLINE_NODEPORT_HTTP};
        proxy_http_version 1.1;
        proxy_request_buffering off;
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_set_header Connection \"\";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
"
    if [[ "$ONLINE_TLS_MODE" == "off" ]]; then
      ONLINE_SCHEME="http"
      ONLINE_HTTP_SERVER="server {
    listen 80;
    listen [::]:80;
    server_name ${ONLINE_HOST};

${ONLINE_LIVEKIT_LOCATION}
${ONLINE_COLLABORATION_LOCATION}
${ONLINE_VIDEO_RELAY_LOCATION}
    location / {
        proxy_pass http://127.0.0.1:${ONLINE_NODEPORT_HTTP};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
"
    else
      ONLINE_LETSENCRYPT_CERT="/etc/letsencrypt/live/${ONLINE_HOST}/fullchain.pem"
      ONLINE_LETSENCRYPT_KEY="/etc/letsencrypt/live/${ONLINE_HOST}/privkey.pem"
      ONLINE_SELF_SIGNED_DIR="/etc/nginx/playsay-online"
      ONLINE_SELF_SIGNED_CERT="${ONLINE_SELF_SIGNED_DIR}/${ONLINE_HOST}.crt"
      ONLINE_SELF_SIGNED_KEY="${ONLINE_SELF_SIGNED_DIR}/${ONLINE_HOST}.key"

      if [[ -f "$ONLINE_LETSENCRYPT_CERT" && -f "$ONLINE_LETSENCRYPT_KEY" ]]; then
        ONLINE_SSL_CERT="$ONLINE_LETSENCRYPT_CERT"
        ONLINE_SSL_KEY="$ONLINE_LETSENCRYPT_KEY"
      elif [[ "$ONLINE_TLS_MODE" == "existing" ]]; then
        echo "ONLINE_TLS_MODE=existing but certificate is missing for ${ONLINE_HOST}" >&2
        exit 1
      else
        mkdir -p "$ONLINE_SELF_SIGNED_DIR"
        chmod 700 "$ONLINE_SELF_SIGNED_DIR"
        if [[ ! -f "$ONLINE_SELF_SIGNED_CERT" || ! -f "$ONLINE_SELF_SIGNED_KEY" ]]; then
          openssl req -x509 -nodes -newkey rsa:2048 \
            -keyout "$ONLINE_SELF_SIGNED_KEY" \
            -out "$ONLINE_SELF_SIGNED_CERT" \
            -days 365 \
            -subj "/CN=${ONLINE_HOST}" \
            -addext "subjectAltName=DNS:${ONLINE_HOST}"
          chmod 600 "$ONLINE_SELF_SIGNED_KEY"
        fi
        ONLINE_SSL_CERT="$ONLINE_SELF_SIGNED_CERT"
        ONLINE_SSL_KEY="$ONLINE_SELF_SIGNED_KEY"
      fi

      ONLINE_HTTP_SERVER="server {
    listen 80;
    listen [::]:80;
    server_name ${ONLINE_HOST};

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
        default_type \"text/plain\";
        try_files \$uri =404;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}
"
      ONLINE_HTTPS_SERVER="server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${ONLINE_HOST};

    ssl_certificate ${ONLINE_SSL_CERT};
    ssl_certificate_key ${ONLINE_SSL_KEY};

${ONLINE_LIVEKIT_LOCATION}
${ONLINE_COLLABORATION_LOCATION}
${ONLINE_VIDEO_RELAY_LOCATION}
    location / {
        proxy_pass http://127.0.0.1:${ONLINE_NODEPORT_HTTP};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
"
    fi

    NGINX_CONF_TARGET="/etc/nginx/conf.d/playsay-k8s-dev.conf"
    NGINX_CONF_BACKUP=""
    if [[ -f "$NGINX_CONF_TARGET" ]]; then
      NGINX_CONF_BACKUP="${NGINX_CONF_TARGET}.bak.$(date +%Y%m%d%H%M%S)"
      cp "$NGINX_CONF_TARGET" "$NGINX_CONF_BACKUP"
    fi

    cat > "$NGINX_CONF_TARGET" <<EOF
server {
    ${OPS_LISTEN_DIRECTIVE}
    server_name ${OPS_HOST};

${OPS_SSL_DIRECTIVES}
${OPS_ALLOW_DIRECTIVES}
    location = / {
        return 302 /headlamp/;
    }

    location /argocd/ {
        proxy_pass http://127.0.0.1:${ARGOCD_NODEPORT_HTTP};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Prefix /argocd;
    }

    location = /argocd {
        return 301 /argocd/;
    }

    location /headlamp/ {
        proxy_pass http://127.0.0.1:${HEADLAMP_NODEPORT_HTTP};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Prefix /headlamp;
    }

    location = /headlamp {
        return 301 /headlamp/;
    }

    location /jenkins/ {
        proxy_pass http://127.0.0.1:${JENKINS_NODEPORT_HTTP};
        proxy_http_version 1.1;
        proxy_request_buffering off;
        proxy_buffering off;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Prefix /jenkins;
    }

    location = /jenkins {
        return 301 /jenkins/;
    }

    location /keycloak/ {
        proxy_pass http://127.0.0.1:${KEYCLOAK_NODEPORT_HTTP};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Port ${OPS_PORT};
        proxy_set_header X-Forwarded-Prefix /keycloak;
    }

    location = /keycloak {
        return 301 /keycloak/;
    }

    location ~ ^/victoria-metrics/(api/v1/admin|debug|flags|metrics) {
        return 403;
    }

    location /victoria-metrics/ {
        proxy_pass http://127.0.0.1:${VICTORIA_METRICS_NODEPORT_HTTP};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Prefix /victoria-metrics;
    }

    location = /victoria-metrics {
        return 301 /victoria-metrics/vmui/;
    }

    location = /vmui {
        return 301 /victoria-metrics/vmui/;
    }

    location /vmui/ {
        return 301 /victoria-metrics/vmui/;
    }
}

${ONLINE_HTTP_SERVER}
${ONLINE_HTTPS_SERVER}
EOF
    if nginx -t; then
      systemctl reload nginx
      if [[ -n "$NGINX_CONF_BACKUP" ]]; then
        rm -f "$NGINX_CONF_BACKUP"
      fi
    else
      echo "Generated nginx config is invalid; restoring previous nginx state." >&2
      if [[ -n "$NGINX_CONF_BACKUP" ]]; then
        mv "$NGINX_CONF_BACKUP" "$NGINX_CONF_TARGET"
      else
        rm -f "$NGINX_CONF_TARGET"
      fi
      nginx -t || true
      exit 1
    fi
  else
    echo "CONFIGURE_HOST_NGINX=true but nginx is not installed; skipping host nginx config."
  fi
fi

kubectl apply -f "$ROOT_DIR/argocd-apps/$ENVIRONMENT/root-app.yaml"

echo "Cluster add-ons installed for $ENVIRONMENT."
echo "Ops URL: ${OPS_SCHEME}://$OPS_HOST:$OPS_PORT"
echo "Online URL: ${ONLINE_SCHEME}://$ONLINE_HOST"
echo "ArgoCD URL: ${OPS_SCHEME}://$OPS_HOST:$OPS_PORT/argocd/"
echo "Headlamp URL: ${OPS_SCHEME}://$OPS_HOST:$OPS_PORT/headlamp/"
echo "VictoriaMetrics URL: ${OPS_SCHEME}://$OPS_HOST:$OPS_PORT/victoria-metrics/vmui/"
if [[ "$INSTALL_JENKINS" == "true" ]]; then
  echo "Jenkins URL: ${OPS_SCHEME}://$OPS_HOST:$OPS_PORT/jenkins/"
  echo "Jenkins admin password command:"
  echo "  kubectl -n jenkins get secret jenkins -o jsonpath='{.data.jenkins-admin-password}' | base64 -d"
fi
echo "Headlamp token command:"
echo "  kubectl -n headlamp get secret headlamp-admin-token -o jsonpath='{.data.token}' | base64 -d"

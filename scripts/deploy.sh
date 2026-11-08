#!/usr/bin/env bash
set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
ROOT="$(git rev-parse --show-toplevel)"
LOCAL_DIR="${ROOT}/site/"
DRY_RUN=false

die() {
    echo "Ошибка: $*" >&2
    exit 1
}

if [[ $# -gt 1 ]]; then
    die "Использование: scripts/deploy.sh [--dry-run]"
fi
if [[ $# -eq 1 ]]; then
    [[ "$1" == "--dry-run" ]] || die "Неизвестный аргумент: $1"
    DRY_RUN=true
fi

[[ -f "${LOCAL_DIR}index.html" ]] || die "Нет site/index.html"
[[ -z "$(git -C "$ROOT" status --porcelain)" ]] ||
    die "Есть незафиксированные изменения"

COMMIT="$(git -C "$ROOT" rev-parse --short HEAD)"
OPTIONS=(-avz --delete --chmod=D755,F644)
if "$DRY_RUN"; then
    OPTIONS+=(--dry-run)
fi

rsync "${OPTIONS[@]}" \
    -e "ssh -o BatchMode=yes -o ConnectTimeout=5" \
    "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}/" ||
    die "Ошибка доставки"

if "$DRY_RUN"; then
    echo "План доставки коммита $COMMIT готов"
    exit 0
fi

curl --fail --silent --show-error \
    --connect-timeout 5 --max-time 15 \
    --cacert "$CA_CERT" "$SITE_URL" -o /dev/null ||
    die "Сайт недоступен или сертификат не прошёл проверку"

echo "Доставлен коммит $COMMIT"

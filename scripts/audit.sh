#!/usr/bin/env bash
set -uo pipefail
export LC_ALL=C
PASS=0; FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "[OK] $desc"
        ((PASS++))
    else
        echo "[FAIL] $desc (ожидалось: '$expected', получено: '$actual')"
        ((FAIL++))
    fi
}

sudo -v || exit 1
SSH_CONFIG=$(sudo sshd -T) || exit 1
UFW_STATUS=$(sudo ufw status verbose) || exit 1

echo "Аудит: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"
echo "[1] Служба SSH"

check "Вход root запрещён" "no" \
    "$(awk '$1=="permitrootlogin"{print $2}' <<< "$SSH_CONFIG")"

check "Парольная аутентификация отключена" "no" \
    "$(awk '$1=="passwordauthentication"{print $2}' <<< "$SSH_CONFIG")"

PORT=$(awk '$1=="port"{print $2}' <<< "$SSH_CONFIG")
if [[ -n "$PORT" ]] && ! grep -qx '22' <<< "$PORT"; then
    check "Порт SSH отличается от 22" "yes" "yes"
else
    check "Порт SSH отличается от 22" "yes" "no"
fi

check "MaxAuthTries равен 3" "3" \
    "$(awk '$1=="maxauthtries"{print $2}' <<< "$SSH_CONFIG")"

echo "[2] Межсетевой экран"

check "Межсетевой экран активен" "active" \
    "$(awk '/^Status:/{print $2}' <<< "$UFW_STATUS")"

check "Входящий трафик по умолчанию запрещён" "deny" \
    "$(sed -n 's/^Default: \([^ ]*\) (incoming).*/\1/p' <<< "$UFW_STATUS")"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Веб-сервер"

check "Nginx активен" "active" "$(systemctl is-active nginx)"

if sudo nginx -t; then
    check "Конфигурация Nginx корректна" "0" "0"
else
    check "Конфигурация Nginx корректна" "0" "1"
fi

CERT_MIN_SECONDS="${CERT_MIN_SECONDS:-2592000}"
if openssl x509 -in /etc/ssl/certs/devops.crt \
    -noout -checkend "$CERT_MIN_SECONDS"; then
    check "Срок действия сертификата достаточен" "0" "0"
else
    check "Срок действия сертификата достаточен" "0" "1"
fi

WRITABLE=$(find /var/www/devops-site -perm -o+w)
FIND_STATUS=$?
KEY_MODE=$(sudo stat -c '%a' /etc/ssl/private/devops.key)
KEY_STATUS=$?

if [[ $FIND_STATUS -eq 0 && $KEY_STATUS -eq 0 &&
      -z "$WRITABLE" && "$KEY_MODE" == "600" ]]; then
    check "Безопасные права сайта и ключа" "yes" "yes"
else
    check "Безопасные права сайта и ключа" "yes" "no"
fi
echo "[5] Контейнеризация"

check "Docker активен" "active" "$(systemctl is-active docker)"

check "БД healthy" "healthy" \
    "$(docker inspect -f '{{.State.Health.Status}}' app-db-1)"

SOCKETS=$(ss -H -tln)
SOCKET_STATUS=$?
BAD_PORTS=$(awk '$4 ~ /:(5000|5432)$/ && $4 !~ /^127\.0\.0\.1:/ {print $4}' <<< "$SOCKETS")

if [[ $SOCKET_STATUS -eq 0 && -z "$BAD_PORTS" ]]; then
    check "Порты приложения и БД закрыты извне" "yes" "yes"
else
    check "Порты приложения и БД закрыты извне" "yes" "no"
fi

check "Права .env равны 600" "600" \
    "$(stat -c '%a' "$HOME/app/.env")"
echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1

# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины
VirtualBox, Ubuntu Server 24.04.5 LTS.
Оперативная память: 2048 МБ, процессоры: 2, диск: 25 ГБ.

## 2. Сетевые интерфейсы
- enp0s3: NAT, 10.0.2.15/24, доступ в Интернет.
- enp0s8: Host-only, 192.168.56.101/24, доступ с хоста.
- Имя узла: devops-vm.
- Полное имя: devops-vm.devops.local.
- В /etc/hosts VM: 127.0.1.1 devops-vm.devops.local devops-vm.
- В hosts Windows: 192.168.56.101 devops.local.

## 3. Правило проброса портов
TCP: 127.0.0.1:2222 хоста → порт 2222 гостя.

## 4. Учётные записи
- vatanshoev: группы vatanshoev, adm, cdrom, sudo, dip, plugdev, lxd.
  Администрирование через консоль VM.
- devops: группы devops, sudo, users. Вход по ключу ED25519.
- Закрытый ключ клиента: ~/.ssh/devops_vm.
- Открытый ключ размещён в ~devops/.ssh/authorized_keys.
- Права .ssh: 700, authorized_keys: 600, владелец devops.
- SSH-алиас клиента:

```sshconfig
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

## 5. Служба SSH
Пакет openssh-server. Основной sshd_config сохранён без изменений,
резервная копия: /etc/ssh/sshd_config.backup.

Файл /etc/ssh/sshd_config.d/99-hardening.conf:

```text
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

Проверка и применение:

```bash
sudo sshd -t
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
sudo ss -tlnp | grep sshd
```

При изменениях сохранять действующую SSH-сессию до проверки нового подключения.

## 6. Правила межсетевого экрана
UFW активен, входящие соединения по умолчанию запрещены,
исходящие разрешены. Правила IPv4 и IPv6:
- 2222/tcp: LIMIT IN, SSH rate-limited.
- 80/tcp: ALLOW IN, HTTP.
- 443/tcp: ALLOW IN, HTTPS.

Восстановление правил:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw enable
sudo ufw logging medium
```

## 7. Снимки состояния
Даты по местному времени, 08.11.2026:
- 01-clean-install — 14:49, исходная установка.
- 03-ssh-hardened — 16:02, защита SSH.
- 04-nginx-https — 16:59, Nginx и HTTPS.
Снимок 02-keys-configured не создан.

## 8. Веб-сервер
Пакет: nginx.
Конфигурация: /etc/nginx/sites-available/devops-site.
Активная ссылка: /etc/nginx/sites-enabled/devops-site.
Стандартная ссылка sites-enabled/default удалена.

Каталог сайта: /var/www/devops-site, владелец devops:devops.
Каталоги: 755, файлы: 644.
Исходники: site/index.html и site/404.html в репозитории.

Сертификат: /etc/ssl/certs/devops.crt, root:root, 644.
Ключ: /etc/ssl/private/devops.key, root:root, 600.
Самоподписанный сертификат действует 365 дней, SAN: DNS:devops.local.
Закрытый ключ в репозиторий не включается.

Команда формирования:

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"
```

Конфигурация ресурса:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name devops.local;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name devops.local;
    ssl_certificate /etc/ssl/certs/devops.crt;
    ssl_certificate_key /etc/ssl/private/devops.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    root /var/www/devops-site;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    error_page 404 /404.html;
    access_log /var/log/nginx/devops-site.access.log;
    error_log /var/log/nginx/devops-site.error.log;
}
```

Подготовка каталога и активация ресурса:

```bash
sudo mkdir -p /var/www/devops-site
sudo chown devops:devops /var/www/devops-site
sudo chmod 755 /var/www/devops-site
sudo ln -s /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

С хоста WSL: скопировать открытый сертификат и доставить сайт:

```bash
scp devops:/etc/ssl/certs/devops.crt ~/devops.crt
bash scripts/deploy.sh --dry-run
bash scripts/deploy.sh
curl --cacert ~/devops.crt -I https://devops.local
```

Скрипт деплоя требует чистого состояния Git.
Скрипт scripts/audit.sh запускается на VM.

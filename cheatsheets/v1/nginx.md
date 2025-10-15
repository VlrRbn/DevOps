# nginx

---

## Установка и базовая структура

```bash
sudo apt install nginx -y
sudo systemctl enable nginx
sudo systemctl start nginx
```

Проверка:

```bash
systemctl status nginx
curl -I http://localhost
```

Основные директории:

```
/etc/nginx/                     # конфиги
/etc/nginx/nginx.conf           # главный конфиг
/etc/nginx/sites-available/     # отдельные сайты (виртуальные хосты)
/etc/nginx/sites-enabled/       # симлинки на активные сайты
/var/www/html/                  # дефолтный web root
/var/log/nginx/                 # логи (access.log, error.log)
```

---

## Создание простого сайта

Создаём файл:

```bash
sudo nano /etc/nginx/sites-available/devops.conf
```

Вставляем:

```
server {
    listen 80;
    server_name devops.local;

    root /var/www/devops;
    index index.html;

    access_log /var/log/nginx/devops_access.log;
    error_log /var/log/nginx/devops_error.log;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

Активируем:

```bash
sudo mkdir -p /var/www/devops
echo "Hello, DevOps world!" | sudo tee /var/www/devops/index.html
sudo ln -s /etc/nginx/sites-available/devops.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

---

## Reverse Proxy

Вот шаблон:

```
server {
    listen 80;
    server_name api.devops.local;

    location / {
        proxy_pass http://10.200.0.2:8080;   # внутренний сервис
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

NGINX теперь выступает как **frontend-гейт**, а  `netns`/контейнер получает только локальный трафик.

---

## HTTPS (Let's Encrypt)

```bash
sudo apt install certbot python3-certbot-nginx -y
sudo certbot --nginx -d example.com
```

Certbot сам обновит конфиг и добавит `ssl_certificate` секции.

Проверить автопродление:

```bash
sudo systemctl status certbot.timer
```

---

## Оптимизация под нагрузку

Файл `/etc/nginx/nginx.conf` → секция `http { ... }`:

```
worker_processes auto;
worker_connections 2048;
keepalive_timeout 65;
client_max_body_size 50M;
gzip on;
```

---

## Проверка и отладка

| Команда | Что делает |
| --- | --- |
| `sudo nginx -t` | Проверка синтаксиса |
| `sudo systemctl reload nginx` | Перезагрузка без даунтайма |
| `sudo journalctl -u nginx -f` | Логи в реальном времени |
| `sudo tail -f /var/log/nginx/error.log` | Ошибки |
| `/var/log/nginx/access.log` | Логи |
| `sudo ss -tulpn | grep nginx` | Проверить, слушает ли nginx порт 80/443 |
| `ls /etc/nginx/sites-enabled/` | Список сайтов |
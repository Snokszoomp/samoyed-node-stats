# LoudSamoyed (Samoyed-Sentry) для Remnawave

samoyed-node-stats / samoyed-loud — твой верный охраник в мире VPN.

Проект “верного самоеда-охранника”: раз в 60 секунд опрашивает Remnawave API и шлёт алерты в Telegram, если:
- нода перестала быть `active`
- нода перегружена по числу подключенных пользователей

## Быстрый старт (через curl)

### Вариант A: скачать `setup.sh` одной командой (без git)

Надёжный вариант (без `| bash`, чтобы ввод работал всегда):

```bash
curl -fsSLO "https://raw.githubusercontent.com/Snokszoomp/samoyed-node-stats/main/setup.sh" && bash setup.sh
```

Wget-версия:

```bash
wget -q "https://raw.githubusercontent.com/Snokszoomp/samoyed-node-stats/main/setup.sh" -O setup.sh && bash setup.sh
```

### Вариант B: скачать через git clone

```bash
git clone "https://github.com/Snokszoomp/samoyed-node-stats.git"
cd samoyed-node-stats
bash setup.sh
```

### Если вы уже в папке проекта

```bash
bash setup.sh
```

Скрипт задаст вопросы (RU/EN), создаст `.env` и запустит:

```bash
docker compose up -d
```

## Ручной запуск

1) Создайте `.env` (см. `.env.example`)
2) Запустите:

```bash
docker compose up -d --build
```

## Логи

```bash
docker compose logs -f loudsamoyed
```

## Примечания по API

Remnawave у разных сборок может отличаться по путям/полям. В `.env` есть:
- `REMNAWAVE_NODES_PATH` — путь к эндпоинту списка нод (по умолчанию `/api/nodes`)
- `REMNAWAVE_VERIFY_TLS` — проверка TLS (по умолчанию `true`)

Если ваша панель отдаёт ноды по другому URL/формату — поправьте `REMNAWAVE_NODES_PATH` и/или обновите парсер в `src/loudsamoyed/main.py`.

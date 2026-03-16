# LoudSamoyed (Samoyed-Sentry) для Remnawave

samoyed-node-stats / samoyed-loud — твой верный охраник в мире VPN.

Проект “верного самоеда-охранника”: раз в 60 секунд опрашивает Remnawave API и шлёт алерты в Telegram, если:
- нода перестала быть `active`
- нода перегружена по числу подключенных пользователей

## Быстрый старт (через curl)

Запуск интерактивной установки:

```bash
curl -fsSL https://example.com/setup.sh | bash
```

Если вы уже в папке проекта, можно так:

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

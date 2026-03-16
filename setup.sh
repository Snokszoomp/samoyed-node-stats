#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="LoudSamoyed"
ENV_FILE=".env"
REPO="Snokszoomp/samoyed-node-stats"
BRANCH="main"
ARCHIVE_URL="https://codeload.github.com/${REPO}/tar.gz/refs/heads/${BRANCH}"

color() { local c="$1"; shift; printf "\033[%sm%s\033[0m" "$c" "$*"; }
bold() { color "1" "$*"; }
green() { color "32" "$*"; }
red() { color "31" "$*"; }
yellow() { color "33" "$*"; }
cyan() { color "36" "$*"; }

line() { printf "%s\n" "------------------------------------------------------------"; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

TTY_IN="/dev/tty"
if [[ ! -r "$TTY_IN" ]]; then
  TTY_IN=""
fi

fetch_url_to_file() {
  local url="$1"
  local out="$2"
  if have_cmd curl; then
    curl -fsSL "$url" -o "$out"
    return
  fi
  if have_cmd wget; then
    wget -q "$url" -O "$out"
    return
  fi
  echo "$(red "Neither curl nor wget found.")"
  exit 1
}

bootstrap_repo_if_needed() {
  # If docker-compose.yml is present, assume we're already in repo root.
  if [[ -f "docker-compose.yml" ]]; then
    return
  fi

  local target_dir="${LOUDSAMOYED_DIR:-$PWD/samoyed-node-stats}"
  mkdir -p "$target_dir"

  if [[ -f "${target_dir}/docker-compose.yml" ]]; then
    cd "$target_dir"
    return
  fi

  echo "$(yellow "Project files not found here.")"
  echo "Downloading ${REPO}@${BRANCH} into: $(cyan "$target_dir")"

  if ! have_cmd tar; then
    echo "$(red "tar not found.")"
    exit 1
  fi

  local tmp
  tmp="$(mktemp -d)"
  local archive="${tmp}/repo.tar.gz"
  fetch_url_to_file "$ARCHIVE_URL" "$archive"

  tar -xzf "$archive" -C "$tmp"

  # GitHub tarball root folder is usually <repo>-<branch>
  local extracted=""
  if [[ -d "${tmp}/samoyed-node-stats-${BRANCH}" ]]; then
    extracted="${tmp}/samoyed-node-stats-${BRANCH}"
  elif [[ -d "${tmp}/samoyed-node-stats-main" ]]; then
    extracted="${tmp}/samoyed-node-stats-main"
  else
    extracted="$(ls -1d "${tmp}/"*/ 2>/dev/null | head -n 1 || true)"
  fi

  if [[ -z "$extracted" || ! -d "$extracted" ]]; then
    echo "$(red "Failed to extract project archive.")"
    exit 1
  fi

  # Copy project files into target dir (avoid rsync dependency)
  cp -a "${extracted}/." "$target_dir/"
  rm -rf "$tmp"

  cd "$target_dir"
}

compose_cmd() {
  if have_cmd docker && docker compose version >/dev/null 2>&1; then
    echo "docker compose"
    return
  fi
  if have_cmd docker-compose; then
    echo "docker-compose"
    return
  fi
  echo ""
}

prompt() {
  local p="$1"
  local def="${2-}"
  local ans
  if [[ -n "$def" ]]; then
    if [[ -n "${TTY_IN}" ]]; then
      read -r -p "$p [$def]: " ans <"${TTY_IN}" || true
    else
      read -r -p "$p [$def]: " ans || true
    fi
    echo "${ans:-$def}"
  else
    if [[ -n "${TTY_IN}" ]]; then
      read -r -p "$p: " ans <"${TTY_IN}" || true
    else
      read -r -p "$p: " ans || true
    fi
    echo "$ans"
  fi
}

prompt_secret() {
  local p="$1"
  local ans
  if [[ -n "${TTY_IN}" ]]; then
    read -r -s -p "$p: " ans <"${TTY_IN}" || true
  else
    read -r -s -p "$p: " ans || true
  fi
  echo
  echo "$ans"
}

write_env_kv() {
  local k="$1"
  local v="$2"
  # minimal escaping for dotenv: wrap in double quotes and escape existing quotes/backslashes
  v="${v//\\/\\\\}"
  v="${v//\"/\\\"}"
  printf "%s=\"%s\"\n" "$k" "$v"
}

banner_ru() {
  line
  echo "$(bold "$PROJECT_NAME") — Самоед-сторож для Remnawave"
  echo "Опросник создаст $(cyan ".env") и запустит контейнеры."
  line
}

banner_en() {
  line
  echo "$(bold "$PROJECT_NAME") — Samoyed Sentry for Remnawave"
  echo "Wizard will create $(cyan ".env") and start containers."
  line
}

main() {
  bootstrap_repo_if_needed

  local compose
  compose="$(compose_cmd)"
  if [[ -z "$compose" ]]; then
    echo "$(red "Docker Compose not found.")"
    echo "Install Docker + Compose, then rerun."
    exit 1
  fi

  echo
  echo "$(bold "Select language / Выберите язык")"
  echo "  1) Русский"
  echo "  2) English"
  local lang
  lang="$(prompt "> " "1")"
  if [[ "$lang" != "1" && "$lang" != "2" ]]; then
    lang="1"
  fi

  if [[ "$lang" == "1" ]]; then
    banner_ru
    echo "$(yellow "Подсказка:") токен Remnawave — это JWT (Bearer). Если у вас куки (Egames) — вставьте их как есть."
  else
    banner_en
    echo "$(yellow "Tip:") Remnawave token is JWT (Bearer). If you use cookies (Egames), paste them as-is."
  fi

  local tg_token tg_chat api_url api_token api_cookies users_limit
  local eg_cookie_name eg_cookie_value

  if [[ "$lang" == "1" ]]; then
    tg_token="$(prompt_secret "Telegram Bot Token")"
    tg_chat="$(prompt "Telegram Chat ID")"
    api_url="$(prompt "API URL панели Remnawave (например https://panel.example.com)")"
    api_token="$(prompt_secret "API Token (JWT, можно пусто если Egames)")"
    eg_cookie_name="$(prompt "Egames Cookie name (можно пусто если JWT)")"
    eg_cookie_value="$(prompt_secret "Egames Cookie value (можно пусто если JWT)")"
    users_limit="$(prompt "Лимит пользователей на ноду" "250")"
  else
    tg_token="$(prompt_secret "Telegram Bot Token")"
    tg_chat="$(prompt "Telegram Chat ID")"
    api_url="$(prompt "Remnawave API URL (e.g. https://panel.example.com)")"
    api_token="$(prompt_secret "API Token (JWT, optional if Egames)")"
    eg_cookie_name="$(prompt "Egames Cookie name (optional if JWT)")"
    eg_cookie_value="$(prompt_secret "Egames Cookie value (optional if JWT)")"
    users_limit="$(prompt "Users limit per node" "250")"
  fi

  if [[ -z "$tg_token" || -z "$tg_chat" || -z "$api_url" ]]; then
    echo "$(red "Missing required values.")"
    echo
    echo "Если вы запускали через пайп (curl | bash), убедитесь что ввод идёт из терминала."
    echo "Рекомендуемый запуск одной командой без пайпа:"
    echo "  curl -fsSLO \"https://raw.githubusercontent.com/Snokszoomp/samoyed-node-stats/main/setup.sh\" && bash setup.sh"
    exit 1
  fi

  {
    echo "# Generated by setup.sh"
    echo
    write_env_kv "TELEGRAM_BOT_TOKEN" "$tg_token"
    write_env_kv "TELEGRAM_CHAT_ID" "$tg_chat"
    echo
    write_env_kv "REMNAWAVE_API_URL" "$api_url"
    write_env_kv "REMNAWAVE_API_TOKEN" "$api_token"
    write_env_kv "REMNAWAVE_EGAMES_COOKIE_NAME" "$eg_cookie_name"
    write_env_kv "REMNAWAVE_EGAMES_COOKIE_VALUE" "$eg_cookie_value"
    write_env_kv "REMNAWAVE_NODES_PATH" "/api/nodes"
    write_env_kv "REMNAWAVE_VERIFY_TLS" "true"
    echo
    write_env_kv "POLL_INTERVAL_SECONDS" "60"
    write_env_kv "NODE_USERS_LIMIT" "$users_limit"
    write_env_kv "OVERLOAD_REPEAT_SECONDS" "600"
    write_env_kv "LOG_LEVEL" "INFO"
    echo
  } > "$ENV_FILE"

  chmod 600 "$ENV_FILE" || true

  if [[ "$lang" == "1" ]]; then
    echo "$(green "Готово:") создан $(cyan "$ENV_FILE")"
    echo "Запускаю контейнеры: $(bold "$compose up -d --build")"
  else
    echo "$(green "Done:") created $(cyan "$ENV_FILE")"
    echo "Starting containers: $(bold "$compose up -d --build")"
  fi

  $compose up -d --build

  if [[ "$lang" == "1" ]]; then
    echo
    echo "$(green "Самоед на посту.") Логи: $(bold "$compose logs -f loudsamoyed")"
  else
    echo
    echo "$(green "Samoyed is on duty.") Logs: $(bold "$compose logs -f loudsamoyed")"
  fi
}

main "$@"


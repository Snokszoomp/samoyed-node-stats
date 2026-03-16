import asyncio
import contextlib
import logging
import os
import time
from dataclasses import dataclass
from typing import Any

import httpx
from aiogram import Bot, Dispatcher
from aiogram.filters import Command
from aiogram.types import Message
from dotenv import load_dotenv


@dataclass(frozen=True)
class NodeSnapshot:
    uuid: str
    name: str
    status: str
    users_online: int | None
    raw: dict[str, Any]


def _env_bool(name: str, default: bool) -> bool:
    v = os.getenv(name)
    if v is None:
        return default
    return v.strip().lower() in {"1", "true", "yes", "y", "on"}


def _derive_status(node: dict[str, Any]) -> str:
    is_disabled = bool(node.get("isDisabled"))
    is_connecting = bool(node.get("isConnecting"))
    is_connected = bool(node.get("isConnected"))

    if is_disabled:
        return "disabled"
    if is_connected:
        return "active"
    if is_connecting:
        return "connecting"
    return "inactive"


def _parse_nodes(payload: Any) -> list[NodeSnapshot]:
    if not isinstance(payload, dict):
        raise ValueError("Nodes payload must be an object")

    items = payload.get("response")
    if not isinstance(items, list):
        raise ValueError("Nodes payload missing 'response' array")

    out: list[NodeSnapshot] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        uuid = str(item.get("uuid") or "")
        name = str(item.get("name") or uuid or "unknown")
        users_online_val = item.get("usersOnline")
        users_online = None
        if isinstance(users_online_val, int):
            users_online = users_online_val
        status = _derive_status(item)
        out.append(
            NodeSnapshot(
                uuid=uuid or name,
                name=name,
                status=status,
                users_online=users_online,
                raw=item,
            )
        )
    return out


async def _fetch_nodes(client: httpx.AsyncClient, nodes_path: str) -> list[NodeSnapshot]:
    r = await client.get(nodes_path)
    r.raise_for_status()
    return _parse_nodes(r.json())


def _samoyed_prefix() -> str:
    return "🐾 LoudSamoyed"


def _msg_node_down(node: NodeSnapshot) -> str:
    return (
        f"⚠️ Самоед лает! Нода [{node.name}] упала!\n"
        f"{_samoyed_prefix()}: держу уши торчком и охраняю стаю."
    )


def _msg_node_overload(node: NodeSnapshot, limit: int) -> str:
    return (
        f"🔥 Нода [{node.name}] перегружена!\n"
        f"Текущая нагрузка: {node.users_online} чел. (лимит: {limit})\n"
        f"{_samoyed_prefix()}: дыхание ровное, но я уже рычу на перегруз."
    )


async def run() -> None:
    load_dotenv()

    log_level = os.getenv("LOG_LEVEL", "INFO").upper()
    logging.basicConfig(
        level=getattr(logging, log_level, logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    log = logging.getLogger("loudsamoyed")

    bot_token = os.environ["TELEGRAM_BOT_TOKEN"]
    chat_id = os.environ["TELEGRAM_CHAT_ID"]
    api_url = os.environ["REMNAWAVE_API_URL"].rstrip("/")
    api_token = os.getenv("REMNAWAVE_API_TOKEN", "").strip()
    cookies = os.getenv("REMNAWAVE_COOKIES", "").strip()
    nodes_path = os.getenv("REMNAWAVE_NODES_PATH", "/api/nodes").strip() or "/api/nodes"
    verify_tls = _env_bool("REMNAWAVE_VERIFY_TLS", True)

    poll_interval = int(os.getenv("POLL_INTERVAL_SECONDS", "60"))
    users_limit = int(os.getenv("NODE_USERS_LIMIT", "250"))
    overload_repeat = int(os.getenv("OVERLOAD_REPEAT_SECONDS", "600"))

    bot = Bot(token=bot_token)
    dp = Dispatcher()

    @dp.message(Command("start"))
    async def _start(m: Message) -> None:
        await m.answer(
            f"{_samoyed_prefix()}: на посту.\n"
            f"Мониторю Remnawave каждые {poll_interval}с."
        )

    headers: dict[str, str] = {}
    if api_token:
        headers["Authorization"] = f"Bearer {api_token}"
    if cookies:
        headers["Cookie"] = cookies

    timeout = httpx.Timeout(20.0, connect=10.0)
    limits = httpx.Limits(max_keepalive_connections=10, max_connections=20)

    previous_status: dict[str, str] = {}
    last_overload_sent: dict[str, float] = {}

    async with httpx.AsyncClient(
        base_url=api_url,
        headers=headers,
        timeout=timeout,
        limits=limits,
        verify=verify_tls,
    ) as client:

        async def monitor_loop() -> None:
            log.info("Samoyed is watching nodes. api_url=%s nodes_path=%s", api_url, nodes_path)
            while True:
                started = time.time()
                try:
                    nodes = await _fetch_nodes(client, nodes_path)
                    log.debug("Fetched %d nodes", len(nodes))
                    now = time.time()

                    for node in nodes:
                        prev = previous_status.get(node.uuid)
                        previous_status[node.uuid] = node.status

                        if prev == "active" and node.status != "active":
                            log.warning("Node down: %s (%s -> %s)", node.name, prev, node.status)
                            await bot.send_message(chat_id, _msg_node_down(node))

                        if node.users_online is not None and node.users_online > users_limit:
                            last = last_overload_sent.get(node.uuid, 0.0)
                            if now - last >= overload_repeat:
                                last_overload_sent[node.uuid] = now
                                log.warning(
                                    "Node overload: %s users=%s limit=%s",
                                    node.name,
                                    node.users_online,
                                    users_limit,
                                )
                                await bot.send_message(
                                    chat_id, _msg_node_overload(node, users_limit)
                                )

                except Exception as e:
                    log.exception("Monitor tick failed: %s", e)

                elapsed = time.time() - started
                sleep_for = max(1.0, poll_interval - elapsed)
                await asyncio.sleep(sleep_for)

        monitor_task = asyncio.create_task(monitor_loop())
        try:
            await dp.start_polling(bot, allowed_updates=dp.resolve_used_update_types())
        finally:
            monitor_task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await monitor_task
            await bot.session.close()


if __name__ == "__main__":
    asyncio.run(run())


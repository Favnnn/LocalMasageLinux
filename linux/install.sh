#!/usr/bin/env bash
# Установка сервера «Мост» на Linux (Debian/Ubuntu/CentOS/Rocky/Alpine и др.).
#
# Что делает:
#   1) кладёт бинарник сервера в /opt/most;
#   2) настраивает автозапуск: через systemd, а если systemd нет — через cron (@reboot);
#   3) открывает порт в firewall (ufw/firewalld), если они активны;
#   4) запускает сервер сразу и печатает адреса.
#
# Запуск:          sudo bash install.sh [порт]     (порт по умолчанию 8410)
# Смена порта:     sudo bash install.sh 9000
#
# Данные чатов хранятся в /opt/most/data — сохраняются при перезагрузках и обновлениях.

set -u

PORT="${1:-8410}"
MOST_DIR="/opt/most"
BIN_NAME="most-server"
SVC_NAME="most"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "=================================================="
echo "  Мост — установка сервера на Linux"
echo "=================================================="

# --- права root ---
if [ "$(id -u)" -ne 0 ]; then
  echo "Нужны права администратора — перезапускаю через sudo…"
  exec sudo bash "$HERE/install.sh" "$@"
fi

# --- архитектура ---
case "$(uname -m)" in
  x86_64)        ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)
    echo "Неизвестная архитектура: $(uname -m). Нужны сборки amd64 или arm64."
    exit 1
    ;;
esac
SRC_BIN="$HERE/${BIN_NAME}-${ARCH}"

# --- источник бинарника: рядом или внутри tar.gz рядом ---
if [ ! -f "$SRC_BIN" ] && [ -f "$HERE/most-server-linux.tar.gz" ]; then
  echo "Распаковываю most-server-linux.tar.gz…"
  mkdir -p "$HERE/.unpack"
  tar -xzf "$HERE/most-server-linux.tar.gz" -C "$HERE/.unpack"
  SRC_BIN="$HERE/.unpack/${BIN_NAME}-${ARCH}"
fi
if [ ! -f "$SRC_BIN" ]; then
  echo "ОШИБКА: не найден файл ${BIN_NAME}-${ARCH} (или most-server-linux.tar.gz) рядом с install.sh"
  exit 1
fi

echo "Архитектура: ${ARCH};  папка установки: ${MOST_DIR};  порт: ${PORT}"
mkdir -p "${MOST_DIR}/data"
cp -f "$SRC_BIN" "${MOST_DIR}/${BIN_NAME}"
chmod 755 "${MOST_DIR}/${BIN_NAME}"

# --- автозапуск и старт ---
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  cat > "/etc/systemd/system/${SVC_NAME}.service" <<UNIT
[Unit]
Description=Мост — сервер обмена сообщениями и файлами
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=${MOST_DIR}
ExecStart=${MOST_DIR}/${BIN_NAME} -port ${PORT} -data ${MOST_DIR}/data -no-open
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  systemctl enable "${SVC_NAME}" >/dev/null 2>&1
  # перезапуск обязателен: enable --now не трогает уже работающую службу,
  # а нам нужно, чтобы сразу работала именно новая версия
  systemctl restart "${SVC_NAME}"
  echo "Автозапуск: systemd — служба «${SVC_NAME}» включена (стартует при каждой загрузке)."
  echo "Логи:        journalctl -u ${SVC_NAME} -f"
else
  # systemd нет — прописываем в cron: строка @reboot стартует сервер при каждой загрузке
  CRON_LINE="@reboot ${MOST_DIR}/${BIN_NAME} -port ${PORT} -data ${MOST_DIR}/data -no-open >> /var/log/most.log 2>&1"
  (crontab -l 2>/dev/null | grep -vF "${MOST_DIR}/${BIN_NAME}" || true; echo "$CRON_LINE") | crontab -
  # и запускаем прямо сейчас
  pkill -f "${MOST_DIR}/${BIN_NAME}" 2>/dev/null || true
  nohup "${MOST_DIR}/${BIN_NAME}" -port "${PORT}" -data "${MOST_DIR}/data" -no-open >> /var/log/most.log 2>&1 &
  echo "Автозапуск: cron (@reboot) — строка добавлена в crontab root."
  echo "Логи:        tail -f /var/log/most.log"
fi

# --- firewall ---
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow "${PORT}/tcp" >/dev/null 2>&1 || true
  echo "Firewall ufw: порт ${PORT}/tcp открыт."
elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port="${PORT}/tcp" >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null 2>&1 || true
  echo "Firewall firewalld: порт ${PORT}/tcp открыт."
fi

sleep 1
# показываем, какая версия реально работает — чтобы при обновлении было видно,
# что запущена новая, а не старая
if command -v curl >/dev/null 2>&1; then
  V=$(curl -s --max-time 3 "http://127.0.0.1:${PORT}/api/info" | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || true)
  if [ -n "${V:-}" ]; then
    echo "Работает версия сервера: ${V}"
  fi
fi
echo ""
echo "--------------------------------------------------"
echo "Проверка работы:   curl -s http://127.0.0.1:${PORT}/api/info"
echo "Интерфейс чата:    http://<адрес-этого-сервера>:${PORT}"
echo "                   (адрес можно узнать: ip addr | grep 'inet ')"
echo "Данные чатов:      ${MOST_DIR}/data"
echo "Удаление:          sudo bash uninstall.sh"
echo "--------------------------------------------------"

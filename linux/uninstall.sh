#!/usr/bin/env bash
# Удаление сервера «Мост» с Linux-машины.
#
#   sudo bash uninstall.sh           — остановить и убрать программу (данные чатов останутся)
#   sudo bash uninstall.sh --purge   — удалить и данные чатов (/opt/most/data) тоже

set -u
MOST_DIR="/opt/most"
SVC_NAME="most"

if [ "$(id -u)" -ne 0 ]; then
  exec sudo bash "$0" "$@"
fi

echo "Останавливаю службу ${SVC_NAME}…"
systemctl disable --now "${SVC_NAME}" 2>/dev/null || true

# убрать строку из cron, если автозапуск был настроен через cron
if command -v crontab >/dev/null 2>&1; then
  (crontab -l 2>/dev/null | grep -vF "${MOST_DIR}/most-server" || true) | crontab - 2>/dev/null || true
  echo "Строка автозапуска удалена из crontab (если была)."
fi

pkill -f "${MOST_DIR}/most-server" 2>/dev/null || true

rm -f "${MOST_DIR}/most-server" "/etc/systemd/system/${SVC_NAME}.service"
systemctl daemon-reload 2>/dev/null || true

if [ "${1:-}" = "--purge" ]; then
  rm -rf "${MOST_DIR}"
  echo "Удалено всё, включая данные чатов (${MOST_DIR})."
else
  echo "Программа удалена. Данные чатов сохранены в ${MOST_DIR}/data —"
  echo "удалить их совсем:  sudo bash uninstall.sh --purge"
fi

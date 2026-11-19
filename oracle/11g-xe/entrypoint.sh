#!/bin/bash
# Oracle 11g XE 启动包装脚本
#
# 流程:
#   1. 复用原镜像的启动脚本(若存在),否则手动启动监听器与实例;
#   2. 轮询等待数据库进入 OPEN 状态(首次启动约需 3~5 分钟);
#   3. 执行 /docker-entrypoint-initdb.d/*.sql(幂等,可挂载自定义脚本);
#   4. 输出 "Database ready to use. Enjoy ;)" 后常驻前台。
#
# 原镜像缺陷修复说明:
#   - 原镜像的启动脚本只打印 "Starting Oracle Net Listener." /
#     "Starting Oracle Database 11g Express Edition instance.",从不提示 ready,
#     使用者无法从日志判断数据库是否就绪;本脚本补充了 OPEN 轮询与 ready 输出。
set -uo pipefail

ORACLE_HOME=${ORACLE_HOME:-/u01/app/oracle/product/11.2.0/xe}
ORACLE_SID=${ORACLE_SID:-XE}
export ORACLE_HOME ORACLE_SID
export LD_LIBRARY_PATH="$ORACLE_HOME/lib:${LD_LIBRARY_PATH:-}"
export PATH="$ORACLE_HOME/bin:$PATH"

CHECK_DB_SQL=/usr/local/share/oracle-init/check-db.sql
INIT_DIR=/docker-entrypoint-initdb.d

log() { echo "[oracle-entrypoint] $*" >&2; }

# 以 oracle 用户执行命令(显式注入环境变量,不依赖 profile)
su_oracle() {
  su -l oracle -c "export ORACLE_HOME='$ORACLE_HOME' ORACLE_SID='$ORACLE_SID' \
LD_LIBRARY_PATH='$ORACLE_HOME/lib' PATH='$ORACLE_HOME/bin':\$PATH; $*"
}

# 手动启动监听器与实例(兜底)
start_db_manually() {
  log "Manually starting Oracle Net Listener..."
  su_oracle "lsnrctl start" || true
  log "Manually starting Oracle Database 11g Express Edition instance..."
  echo 'startup;' | su_oracle "sqlplus -s / as sysdba" || true
}

# 轮询等待数据库 OPEN;参数:最长等待秒数
wait_db_open() {
  local deadline=$(( $(date +%s) + $1 ))
  local status
  while [ "$(date +%s)" -lt "$deadline" ]; do
    status=$(su_oracle "sqlplus -s / as sysdba @$CHECK_DB_SQL" 2>/dev/null | tr -d '[:space:]')
    if [ "$status" = "OPEN" ]; then
      return 0
    fi
    sleep 3
  done
  return 1
}

# ---------- 1. 启动数据库 ----------
orig_startup=""
for candidate in /usr/sbin/startup.sh /usr/local/bin/startup.sh \
                 /usr/local/bin/docker-entrypoint.sh /docker-entrypoint.sh; do
  if [ -x "$candidate" ]; then
    orig_startup="$candidate"
    break
  fi
done

if [ -n "$orig_startup" ]; then
  log "Launching original startup script: $orig_startup"
  ( "$orig_startup" ) || true &
else
  log "No original startup script found, starting database manually"
  start_db_manually
fi

# ---------- 2. 等待数据库 OPEN ----------
log "Waiting for database to OPEN (first boot usually takes 3~5 minutes)..."
if wait_db_open 360; then
  log "Database instance is OPEN."
else
  log "WARN: not OPEN within the expected time, retrying with manual startup..."
  start_db_manually
  if wait_db_open 300; then
    log "Database instance is OPEN."
  else
    log "ERROR: database did not reach OPEN state in ~11 minutes."
    log "       Check the ORA- errors above; common causes: low memory, bad oradata volume."
    exit 1
  fi
fi

# ---------- 3. 执行初始化脚本(幂等) ----------
shopt -s nullglob
for f in "$INIT_DIR"/*.sql; do
  log "Running init script: $(basename "$f")"
  if su_oracle "sqlplus -s / as sysdba @'$f'"; then
    log "Init script $(basename "$f") finished."
  else
    log "WARN: init script $(basename "$f") failed (non-fatal, continuing)."
  fi
done
shopt -u nullglob

# ---------- 4. 启动完成 ----------
echo ""
echo "#############################################"
echo "  Database ready to use. Enjoy ;)"
echo "#############################################"
echo ""

exec tail -f /dev/null

#!/bin/bash
# Oracle 11g EE 启动包装脚本
#
# 与 11g-xe 版的差异:EE base 镜像(yycx/oracle11)的 ORACLE_HOME/SID 未公开约定,
# 本脚本在运行时动态探测:
#   1. ORACLE_HOME:先读 oracle 用户 profile,失败则扫描文件系统中的 sqlplus;
#   2. ORACLE_SID:读 /etc/oratab 第一个实例;
#   3. 启动策略与 XE 版一致:复用原启动脚本(若存在)→ 手动 lsnrctl + startup 兜底。
set -uo pipefail

CHECK_DB_SQL=/usr/local/share/oracle-init/check-db.sql
INIT_DIR=/docker-entrypoint-initdb.d

log() { echo "[oracle-entrypoint] $*" >&2; }

# ---------- 0. 探测 ORACLE_HOME / ORACLE_SID ----------
detect_oracle_env() {
  local probe home sid

  probe=$(su -l oracle -c 'echo "$ORACLE_HOME"' 2>/dev/null || true)
  home=$(echo "$probe" | tr -d '[:space:]')
  if [ -z "$home" ] || [ ! -x "$home/bin/sqlplus" ]; then
    log "ORACLE_HOME not found via oracle profile, scanning filesystem..."
    home=$(find /opt/oracle /u01/app -maxdepth 7 -type f -name sqlplus 2>/dev/null \
            | head -1 | xargs -r dirname | xargs -r dirname)
  fi
  if [ -z "$home" ] || [ ! -x "$home/bin/sqlplus" ]; then
    log "ERROR: cannot locate ORACLE_HOME (sqlplus not found)."
    log "       The base image layout may differ; please inspect the image and adjust."
    exit 1
  fi

  sid=$(grep -v -e '^#' -e '^$' /etc/oratab 2>/dev/null | head -1 | cut -d: -f1 | tr -d '[:space:]')
  if [ -z "$sid" ]; then
    log "WARN: /etc/oratab empty or missing, defaulting ORACLE_SID to orcl"
    sid=orcl
  fi

  echo "$home $sid"
}

read -r ORACLE_HOME ORACLE_SID <<< "$(detect_oracle_env)"
log "Detected ORACLE_HOME=$ORACLE_HOME ORACLE_SID=$ORACLE_SID"
export ORACLE_HOME ORACLE_SID
export LD_LIBRARY_PATH="$ORACLE_HOME/lib:${LD_LIBRARY_PATH:-}"
export PATH="$ORACLE_HOME/bin:$PATH"

# 以 oracle 用户执行命令(显式注入环境变量,不依赖 profile)
su_oracle() {
  su -l oracle -c "export ORACLE_HOME='$ORACLE_HOME' ORACLE_SID='$ORACLE_SID' \
LD_LIBRARY_PATH='$ORACLE_HOME/lib' PATH='$ORACLE_HOME/bin':\$PATH; $*"
}

# 手动启动监听器与实例(兜底)
start_db_manually() {
  log "Manually starting Oracle Net Listener..."
  su_oracle "lsnrctl start" || true
  log "Manually starting Oracle Database instance..."
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
log "Waiting for database to OPEN (first boot usually takes several minutes)..."
if wait_db_open 480; then
  log "Database instance is OPEN."
else
  log "WARN: not OPEN within the expected time, retrying with manual startup..."
  start_db_manually
  if wait_db_open 300; then
    log "Database instance is OPEN."
  else
    log "ERROR: database did not reach OPEN state in ~13 minutes."
    log "       Check the ORA- errors above; common causes: low memory, bad oradata volume,"
    log "       wrong ownership on data dirs (should be owned by the oracle user)."
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

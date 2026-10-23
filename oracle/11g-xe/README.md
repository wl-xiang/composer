# Oracle 11g XE 部署

基于社区镜像 [oracleinanutshell/oracle-xe-11g](https://hub.docker.com/r/oracleinanutshell/oracle-xe-11g) 的
**Oracle Database 11g Express Edition (XE)** Docker Compose 部署方案。

> ⚠️ **许可与用途**:Oracle 11g 属遗留版本,Oracle 官方未提供官方 Docker 镜像。本方案使用的均为社区镜像,
> **仅限开发、测试与学习使用**;生产环境请使用受支持的 Oracle 版本(19c 及以上)、官方镜像并自行解决授权。

## 文件说明

| 文件 | 说明 |
| --- | --- |
| `docker-compose.yml` | Compose 编排文件(单容器) |
| `.env.example` | 环境变量模板,复制为 `.env` 后使用 |
| `volumes/oradata/` | 数据库数据文件(oradata),运行后生成 |
| `volumes/dump/` | Data Pump(`expdp`/`impdp`)导入导出目录 |

## 前置要求

- Docker Engine(含 Compose v2 插件)。
- 内存:建议至少 2GB(数据库启动阶段会占用较多内存)。
- 磁盘:建议预留 10GB 以上。
- 宿主机端口 `1521` 未被占用(可在 `.env` 中通过 `ORACLE_XE_PORT` 修改)。

## 快速开始

```bash
cd oracle/11g-xe

# 1. 准备环境变量与数据目录
cp .env.example .env
mkdir -p volumes/oradata volumes/dump

# 2. 启动(首次启动需 3~5 分钟初始化数据库)
docker compose up -d

# 3. 观察初始化日志,出现 "Database ready to use" 即表示启动成功
docker logs -f oracle-11g-xe
```

## 连接信息

| 参数 | 值 |
| --- | --- |
| 主机 | `localhost`(或服务器 IP) |
| 端口 | `1521`(可在 `.env` 中修改) |
| SID | `XE` |
| 用户名 | `system` |
| 密码 | `oracle` |

```bash
# 进入容器使用 SQL*Plus
docker exec -it oracle-11g-xe sqlplus system/oracle

# 或使用 SYSDBA 权限(容器内已预置操作系统认证,无需密码)
docker exec -it oracle-11g-xe sqlplus / as sysdba
```

JDBC 连接串:

```
jdbc:oracle:thin:@localhost:1521:XE
```

> 客户端连接时若报 `ORA-28001: the password will expire` ,说明镜像的默认密码策略过期,
> 见下文「密码策略」一节。

---

## 初始化数据库配置(重要)

> **核心建议:不要用 `system` 用户直接建业务表。**
>
> `system` / `sys` 属于 Oracle 系统账号,它们的数据存放在 `SYS`/`SYSTEM` 这类系统 schema 下。
> 直接用系统账号建表,会造成以下问题:
>
> - 业务表和系统表混在一起,分不清哪些是系统对象、哪些是自己的数据;
> - 系统账号权限过大,一旦误操作 `DROP TABLE` 或 `TRUNCATE`,可能损坏系统表,导致实例无法正常启动;
> - 权限无法单独回收,也无法按业务维度做数据隔离与备份。
>
> **推荐做法:新建一个自己的 DBA 用户**(拥有 `DBA` 权限),在自己的 schema 下建表空间、建表,
> 这样自己的对象和系统对象彻底分离,互不影响。

### 第 1 步:以 SYSDBA 身份连接

```bash
docker exec -it oracle-11g-xe sqlplus / as sysdba
```

### 第 2 步:创建你自己的用户(建议授予 DBA 权限)

```sql
-- 建议使用 12c 以上的扩展密码语法,避免密码被转成大写
CREATE USER appdba IDENTIFIED BY "YourStrong#Passw0rd"
  DEFAULT TABLESPACE USERS
  TEMPORARY TABLESPACE TEMP
  QUOTA UNLIMITED ON USERS
  ACCOUNT UNLOCK;

-- 授予 DBA 权限:该用户拥有独立的 schema,建表时会建在自己的 schema 下,
-- 不会与 system 用户的表混在一起
GRANT DBA TO appdba;
```

验证:

```sql
-- 查看用户是否创建成功及默认表空间
SELECT username, default_tablespace, temporary_tablespace, account_status
  FROM dba_users
 WHERE username = 'APPDBA';
```

### 第 3 步:为业务创建独立的表空间

先确认数据文件所在目录(不同镜像/版本路径可能不同,以实际查询结果为准):

```sql
SELECT name FROM v$datafile;
-- 例:/u01/app/oracle/oradata/XE/system01.dbf

SELECT name FROM v$tempfile;
```

再创建业务表空间(路径使用上一步查到的目录):

```sql
-- 业务表空间
CREATE TABLESPACE APP_TS
  DATAFILE '/u01/app/oracle/oradata/XE/app_ts1.dbf'
  SIZE 100M
  AUTOEXTEND ON NEXT 50M
  MAXSIZE 1G;

-- 业务临时表空间(可选)
CREATE TEMPORARY TABLESPACE APP_TEMP
  TEMPFILE '/u01/app/oracle/oradata/XE/app_temp1.dbf'
  SIZE 50M
  AUTOEXTEND ON NEXT 20M
  MAXSIZE 500M;
```

然后把新用户默认表空间指向它:

```sql
ALTER USER appdba DEFAULT TABLESPACE APP_TS
  TEMPORARY TABLESPACE APP_TEMP
  QUOTA UNLIMITED ON APP_TS;
```

> 新建的数据文件必须落在已挂载的宿主机目录中(默认 `./volumes/oradata`),
> 否则容器重建后数据会丢失。确认路径:

```sql
SELECT file_name FROM dba_data_files WHERE tablespace_name = 'APP_TS';
```

### 第 4 步:切换到新用户,创建自己的表

```sql
CONNECT appdba/"YourStrong#Passw0rd"

CREATE TABLE T_USER (
  ID          NUMBER(10) PRIMARY KEY,
  USER_NAME   VARCHAR2(100) NOT NULL,
  REMARK      VARCHAR2(500),
  CREATED_AT  DATE DEFAULT SYSDATE,
  STATUS      NUMBER(1) DEFAULT 1
);

COMMENT ON TABLE T_USER IS '用户表';
COMMENT ON COLUMN T_USER.ID IS '主键ID';
COMMENT ON COLUMN T_USER.STATUS IS '状态:1-有效,0-无效';

CREATE SEQUENCE SEQ_T_USER START WITH 1 INCREMENT BY 1;

INSERT INTO T_USER (USER_NAME, REMARK) VALUES ('张三', '第一条测试记录');
INSERT INTO T_USER (USER_NAME, REMARK) VALUES ('李四', '第二条测试记录');
COMMIT;

SELECT * FROM T_USER;
```

此时 `T_USER` 属于 `APPDBA` schema,与 `SYSTEM` schema 下的系统表完全分离:

```sql
-- 查看某个 schema 下的对象
SELECT owner, table_name FROM dba_tables WHERE owner = 'APPDBA';

-- 查看各 schema 的对象数量,确认业务表没有混进 SYSTEM
SELECT owner, COUNT(*) FROM dba_objects WHERE object_type = 'TABLE' GROUP BY owner;
```

### 第 5 步:权限建议

| 场景 | 建议做法 |
| --- | --- |
| 应用连接账号 | **不要**授予 `DBA`,只授予 `CONNECT`、`RESOURCE` 及所需对象的 `SELECT`/`INSERT`/`UPDATE`/`DELETE` |
| 本地开发/测试账号 | 可授予 `DBA`,便于建表、调错 |
| 跨 schema 访问 | 优先用 `GRANT SELECT ON APPDBA.T_USER TO other_user`,**不建议**使用 `SELECT ANY TABLE` 等 ANY 权限,否则又会和系统表混在一起 |

创建最小权限应用账号示例:

```sql
CREATE USER app_user IDENTIFIED BY "AppUser#Passw0rd"
  DEFAULT TABLESPACE APP_TS
  TEMPORARY TABLESPACE APP_TEMP
  QUOTA UNLIMITED ON APP_TS;

GRANT CONNECT, RESOURCE TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON APPDBA.T_USER TO app_user;
```

### 第 6 步:Data Pump 目录(导入导出)

镜像内默认的 `DATA_PUMP_DIR` 未必指向挂载目录,如遇 `ORA-12555` / `ORA-39002` 可手动创建:

```sql
CREATE OR REPLACE DIRECTORY DATA_PUMP_DIR AS '/u01/app/oracle/dpdump';
GRANT READ, WRITE ON DIRECTORY DATA_PUMP_DIR TO appdba;
```

---

## 密码与账号维护

### 修改 system 密码

```sql
ALTER USER SYSTEM IDENTIFIED BY "YourStrong#Passw0rd";
```

### 密码永不过期 / 取消登录失败锁定

XE 镜像默认密码策略会在若干天后过期,开发环境建议放开:

```sql
ALTER PROFILE DEFAULT LIMIT PASSWORD_LIFE_TIME UNLIMITED;
ALTER PROFILE DEFAULT LIMIT FAILED_LOGIN_ATTEMPTS UNLIMITED;
```

### 忘记密码怎么办

用容器内的操作系统认证进入(不需要数据库密码):

```bash
docker exec -it oracle-11g-xe sqlplus / as sysdba
```

然后执行 `ALTER USER ... IDENTIFIED BY ...` 重置。

---

## 常用运维命令

```bash
# 查看状态
docker compose ps
docker logs -f oracle-11g-xe

# 停止(数据保留)
docker compose down

# 重启
docker compose restart

# 备份(逻辑备份,导出到挂载的 dump 目录)
docker exec -it oracle-11g-xe expdp appdba/"YourStrong#Passw0rd" \
  DIRECTORY=DATA_PUMP_DIR DUMPFILE=backup.dmp FULL=y

# 导入
docker exec -it oracle-11g-xe impdp appdba/"YourStrong#Passw0rd" \
  DIRECTORY=DATA_PUMP_DIR DUMPFILE=backup.dmp FULL=y LOGFILE=imp.log

# 进入 SQL*Plus
docker exec -it oracle-11g-xe sqlplus / as sysdba
```

数据文件备份(物理备份,需先停库):

```bash
docker compose down
tar czf oracle-xe-oradata-$(date +%F).tar.gz volumes/oradata
docker compose up -d
```

---

## 常见问题

| 现象 | 原因与处理 |
| --- | --- |
| 启动很慢 / 一直不 ready | XE 首次初始化需要 3~5 分钟,用 `docker logs -f` 观察,耐心等待 |
| 容器反复重启 | 多为内存不足,宿主机至少留 2GB 给容器;或端口冲突 |
| 端口冲突 | 修改 `.env` 中的 `ORACLE_XE_PORT`(例如 `1523`) |
| `ORA-28001` 密码过期 | 执行上文「密码策略」放开 `PASSWORD_LIFE_TIME` |
| `ORA-01017` 用户名/密码错误 | 用 `sqlplus / as sysdba` 进入后 `ALTER USER SYSTEM IDENTIFIED BY ...` 重置 |
| 重启容器后数据丢失 | 检查 `volumes/oradata` 是否被正确挂载,以及数据文件是否真的写在挂载目录内 |
| 找不到 `DATA_PUMP_DIR` | 按上文「第 6 步」手动创建 directory 对象 |

---

## 参考

- [oracleinanutshell/oracle-xe-11g](https://hub.docker.com/r/oracleinanutshell/oracle-xe-11g)
- [Oracle Database 11g XE 官方文档](https://docs.oracle.com/en/database/112/xe_erefs/index.html)
- [使用 Docker Compose 快速部署 Oracle 11G 与 RustFS](https://blog.csdn.net/weixin_62018471/article/details/160839074)

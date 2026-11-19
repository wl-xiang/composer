# Oracle 11g XE 部署(优化镜像)

基于社区镜像 [oracleinanutshell/oracle-xe-11g](https://hub.docker.com/r/oracleinanutshell/oracle-xe-11g)
二次构建的 **Oracle Database 11g Express Edition (XE)** 优化镜像 Docker Compose 部署方案。

> ⚠️ **许可与用途**:Oracle 11g 属遗留版本,Oracle 官方未提供官方 Docker 镜像。本方案 base 为社区镜像,
> **仅限开发、测试与学习使用**;生产环境请使用受支持的 Oracle 版本(19c 及以上)、官方镜像并自行解决授权。

## 相对原镜像的修复与优化

| 问题 | 优化镜像的表现 |
| --- | --- |
| `docker exec ... sqlplus` 报 `executable file not found in $PATH` | `sqlplus`/`lsnrctl`/`expdp` 等已加入全局 `PATH`,可直接执行 |
| 启动日志只打印 `Starting Oracle Net Listener.` / `Starting Oracle Database 11g Express Edition instance.`,永远等不到 ready 提示(原镜像根本不输出该日志) | entrypoint 轮询数据库 OPEN 后打印 `Database ready to use. Enjoy ;)` |
| 需要手动建业务用户 | 预置用户 **`oracle1`**(密码 `oracle1`),拥有 `CONNECT`/`RESOURCE`/`DBA` 全权限,独立 schema,开箱即用 |
| 无自定义初始化入口 | 支持挂载 `/docker-entrypoint-initdb.d/*.sql`,每次启动幂等执行 |

## 文件说明

| 文件 | 说明 |
| --- | --- |
| `docker-compose.yml` | Compose 编排文件(单容器,含 build 配置) |
| `Dockerfile` | 优化镜像构建文件(amd64/arm64 通用) |
| `entrypoint.sh` | 启动包装脚本:启动数据库 → 等待 OPEN → 执行初始化 → 输出 ready |
| `check-db.sql` | 数据库状态探测脚本(entrypoint 轮询用) |
| `initdb/01-create-oracle1.sql` | 预置用户 oracle1 的幂等初始化 SQL |
| `build.sh` | 多架构构建脚本(amd64/arm64) |
| `.env.example` | 环境变量模板,复制为 `.env` 后使用 |
| `volumes/oradata/` | 数据库数据文件(oradata),运行后生成 |
| `volumes/dump/` | Data Pump(`expdp`/`impdp`)导入导出目录 |

## 前置要求

- Docker Engine(含 Compose v2 插件与 buildx)。
- 内存:建议至少 2GB(数据库启动阶段会占用较多内存)。
- 磁盘:建议预留 10GB 以上。
- 宿主机端口 `1521` 未被占用(可在 `.env` 中通过 `ORACLE_XE_PORT` 修改)。
- **arm64 宿主机(如 Apple Silicon)**:Oracle 11g 只有 x86-64 二进制,arm64 镜像通过
  qemu/Rosetta 模拟运行,启动更慢、性能打折,仅供开发测试。

## 快速开始

```bash
cd oracle/11g-xe

# 1. 准备环境变量与数据目录
cp .env.example .env
mkdir -p volumes/oradata volumes/dump

# 2. 构建优化镜像并启动(首次启动需 3~5 分钟初始化数据库)
docker compose up -d --build

# 3. 观察初始化日志,出现 "Database ready to use. Enjoy ;)" 即表示启动成功
docker logs -f oracle-11g-xe
```

也可用构建脚本单独构建镜像:

```bash
./build.sh                          # 本机构建 → oracle-xe-11g:1.0.0
PUSH=1 ./build.sh myrepo/oracle-xe-11g:1.0.0   # 双架构(amd64+arm64)构建并推送
```

> 已有旧部署(oradata 已存在)直接换用新镜像即可:`docker compose up -d --build`。
> 注意:旧 `.env` 中的 `ORACLE_XE_IMAGE` 仍是 `oracleinanutshell/oracle-xe-11g:latest`,
> 需同步改为 `oracle-xe-11g:1.0.0`(即复制一份新的 `.env.example` 再合并自己的修改)。
> 初始化脚本幂等,oracle1 用户已存在时会自动跳过。

## 连接信息

| 参数 | 值 |
| --- | --- |
| 主机 | `localhost`(或服务器 IP) |
| 端口 | `1521`(可在 `.env` 中修改) |
| SID | `XE` |
| 业务用户(推荐) | `oracle1` / `oracle1`(拥有增删改查、建表等全权限) |
| 管理员 | `system` / `oracle`(仅做管理用途,不要用来建业务表) |

```bash
# 用业务用户连接(开箱即用)
docker exec -it oracle-11g-xe sqlplus oracle1/oracle1

# 以 SYSDBA 身份进入(容器内已预置操作系统认证,无需密码)
docker exec -it oracle-11g-xe sqlplus / as sysdba
```

JDBC 连接串(业务用户):

```
jdbc:oracle:thin:@localhost:1521:XE
```

> 客户端连接时若报 `ORA-28001: the password will expire`,说明用的是旧数据且密码策略未放开,
> 见下文「密码策略」一节(优化镜像启动时会自动执行放开语句)。

## 上手即用:用 oracle1 建表

`oracle1` 拥有 DBA 权限且与 `system` 的表完全隔离,登录后即可建表:

```bash
docker exec -it oracle-11g-xe sqlplus oracle1/oracle1
```

```sql
CREATE TABLE T_USER (
  ID          NUMBER(10) PRIMARY KEY,
  USER_NAME   VARCHAR2(100) NOT NULL,
  REMARK      VARCHAR2(500),
  CREATED_AT  DATE DEFAULT SYSDATE,
  STATUS      NUMBER(1) DEFAULT 1
);

COMMENT ON TABLE T_USER IS '用户表';
COMMENT ON COLUMN T_USER.STATUS IS '状态:1-有效,0-无效';

CREATE SEQUENCE SEQ_T_USER START WITH 1 INCREMENT BY 1;

INSERT INTO T_USER (USER_NAME, REMARK) VALUES ('张三', '第一条测试记录');
INSERT INTO T_USER (USER_NAME, REMARK) VALUES ('李四', '第二条测试记录');
COMMIT;

SELECT * FROM T_USER;
```

确认业务表都在自己的 schema 下:

```sql
SELECT owner, table_name FROM dba_tables WHERE owner = 'ORACLE1';

-- 业务对象数量与系统对象分离确认
SELECT owner, COUNT(*) FROM dba_objects WHERE object_type = 'TABLE' GROUP BY owner;
```

---

## 镜像构建说明(Dockerfile)

- base 为 `oracleinanutshell/oracle-xe-11g`(仅提供 amd64),arm64 镜像在 qemu/Rosetta 模拟下运行。
- `Dockerfile` 中 `FROM --platform=linux/amd64` 固定 base 架构,保证双架构构建可复现。
- `entrypoint.sh` 的启动策略:
  1. 优先复用 base 镜像自带的启动脚本(探测 `/usr/sbin/startup.sh` 等常见路径);
  2. 找不到则手动 `lsnrctl start` + `startup`;
  3. 轮询 `v$instance.status` 直到 `OPEN`(最长约 11 分钟,超时退出便于发现问题);
  4. 依次执行 `/docker-entrypoint-initdb.d/*.sql`(幂等);
  5. 输出 `Database ready to use. Enjoy ;)` 后常驻前台。

## 自定义初始化脚本

把 SQL 放进 `volumes/initdb/` 并启用 compose 中对应挂载,即可在每次启动时自动执行(幂等):

```yaml
    volumes:
      - ${ORACLE_XE_INIT_DIR:-./volumes/initdb}:/docker-entrypoint-initdb.d
```

---

## 初始化数据库配置(进阶)

> **核心建议:不要用 `system` 用户直接建业务表。**
>
> `system` / `sys` 属于 Oracle 系统账号,直接用系统账号建表,会造成以下问题:
>
> - 业务表和系统表混在一起,分不清哪些是系统对象、哪些是自己的数据;
> - 系统账号权限过大,一旦误操作 `DROP TABLE` 或 `TRUNCATE`,可能损坏系统表,导致实例无法正常启动;
> - 权限无法单独回收,也无法按业务维度做数据隔离与备份。
>
> 优化镜像已预置 `oracle1`(DBA 权限)解决上述问题;如需更多业务用户,可参考下文手动创建。

### 第 1 步:以 SYSDBA 身份连接

```bash
docker exec -it oracle-11g-xe sqlplus / as sysdba
```

### 第 2 步:创建其他业务用户(可选,建议授予 DBA 权限)

```sql
CREATE USER appdba IDENTIFIED BY "YourStrong#Passw0rd"
  DEFAULT TABLESPACE USERS
  TEMPORARY TABLESPACE TEMP
  QUOTA UNLIMITED ON USERS
  ACCOUNT UNLOCK;

GRANT DBA TO appdba;
```

验证:

```sql
SELECT username, default_tablespace, temporary_tablespace, account_status
  FROM dba_users
 WHERE username = 'APPDBA';
```

### 第 3 步:为业务创建独立的表空间(可选)

先确认数据文件所在目录:

```sql
SELECT name FROM v$datafile;
-- 例:/u01/app/oracle/oradata/XE/system01.dbf
```

再创建业务表空间(路径使用上一步查到的目录):

```sql
CREATE TABLESPACE APP_TS
  DATAFILE '/u01/app/oracle/oradata/XE/app_ts1.dbf'
  SIZE 100M
  AUTOEXTEND ON NEXT 50M
  MAXSIZE 1G;
```

然后把新用户默认表空间指向它:

```sql
ALTER USER appdba DEFAULT TABLESPACE APP_TS QUOTA UNLIMITED ON APP_TS;
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

INSERT INTO T_USER (USER_NAME, REMARK) VALUES ('张三', '第一条测试记录');
COMMIT;

SELECT * FROM T_USER;
```

### 权限建议

| 场景 | 建议做法 |
| --- | --- |
| 应用连接账号 | **不要**授予 `DBA`,只授予 `CONNECT`、`RESOURCE` 及所需对象的 `SELECT`/`INSERT`/`UPDATE`/`DELETE` |
| 本地开发/测试账号 | 可授予 `DBA`(预置的 `oracle1` 即此定位),便于建表、调错 |
| 跨 schema 访问 | 优先用 `GRANT SELECT ON ORACLE1.T_USER TO other_user`,**不建议**使用 `SELECT ANY TABLE` 等 ANY 权限 |

### Data Pump 目录(导入导出)

镜像内默认的 `DATA_PUMP_DIR` 未必指向挂载目录,如遇 `ORA-12555` / `ORA-39002` 可手动创建:

```sql
CREATE OR REPLACE DIRECTORY DATA_PUMP_DIR AS '/u01/app/oracle/dpdump';
GRANT READ, WRITE ON DIRECTORY DATA_PUMP_DIR TO ORACLE1;
```

---

## 密码与账号维护

### 修改 system / oracle1 密码

```sql
ALTER USER SYSTEM IDENTIFIED BY "YourStrong#Passw0rd";
ALTER USER ORACLE1 IDENTIFIED BY "YourStrong#Passw0rd";
```

### 密码永不过期 / 取消登录失败锁定

优化镜像启动时会自动执行以下语句;旧数据如有需要也可手动执行:

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

# 重新构建镜像(修改 Dockerfile/entrypoint/initdb 后)
docker compose build

# 备份(逻辑备份,导出到挂载的 dump 目录)
docker exec -it oracle-11g-xe expdp oracle1/oracle1 \
  DIRECTORY=DATA_PUMP_DIR DUMPFILE=backup.dmp FULL=y

# 导入
docker exec -it oracle-11g-xe impdp oracle1/oracle1 \
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
| 启动很慢 / 一直不 ready | XE 首次初始化需要 3~5 分钟(arm64 模拟下更久),用 `docker logs -f` 观察,耐心等待;entrypoint 超时会显式报错 |
| `sqlplus: executable file not found` | 仍在使用旧镜像(未优化前),按「快速开始」执行 `docker compose up -d --build` |
| 容器反复重启 | 多为内存不足,宿主机至少留 2GB 给容器;或端口冲突 |
| 端口冲突 | 修改 `.env` 中的 `ORACLE_XE_PORT`(例如 `1523`) |
| `ORA-28001` 密码过期 | 执行上文「密码策略」放开 `PASSWORD_LIFE_TIME` |
| `ORA-01017` 用户名/密码错误 | 用 `sqlplus / as sysdba` 进入后 `ALTER USER ... IDENTIFIED BY ...` 重置 |
| 重启容器后数据丢失 | 检查 `volumes/oradata` 是否被正确挂载,以及数据文件是否真的写在挂载目录内 |
| 找不到 `DATA_PUMP_DIR` | 按上文「Data Pump 目录」手动创建 directory 对象 |
| arm64 上启动特别慢 | 属正常现象:Oracle 11g 无 ARM 原生二进制,在 qemu/Rosetta 模拟下运行,仅供开发测试 |

---

## 参考

- [oracleinanutshell/oracle-xe-11g](https://hub.docker.com/r/oracleinanutshell/oracle-xe-11g)
- [Oracle Database 11g XE 官方文档](https://docs.oracle.com/en/database/112/xe_erefs/index.html)
- [使用 Docker Compose 快速部署 Oracle 11G 与 RustFS](https://blog.csdn.net/weixin_62018471/article/details/160839074)

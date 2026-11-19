# Oracle 11g 部署(Enterprise Edition,优化镜像)

基于社区镜像 [yycx/oracle11:11.2.0.4](https://hub.docker.com/r/yycx/oracle11)
二次构建的 **Oracle Database 11g Enterprise Edition** 优化镜像 Docker Compose 部署方案,实例 SID 为 `orcl`。

> ⚠️ **许可与用途**:Oracle 11g 属遗留版本,Oracle 官方未提供官方 Docker 镜像。本方案 base 为社区镜像,
> **仅限开发、测试与学习使用**;生产环境请使用受支持的 Oracle 版本(19c 及以上)、官方镜像并自行解决授权。
>
> 镜像体积约 7.35GB(base 即如此),首次构建/拉取请预留足够时间与磁盘空间。

## 相对原镜像的修复与优化

| 问题 | 优化镜像的表现 |
| --- | --- |
| 启动日志无就绪提示,无法判断数据库是否初始化完成 | entrypoint 自动探测 `ORACLE_HOME`/`ORACLE_SID`,轮询数据库 OPEN 后打印 `Database ready to use. Enjoy ;)` |
| 需要手动建业务用户 | 预置用户 **`oracle1`**(密码 `oracle1`),拥有 `CONNECT`/`RESOURCE`/`DBA` 全权限,独立 schema,开箱即用 |
| 无自定义初始化入口 | 支持挂载 `/docker-entrypoint-initdb.d/*.sql`,每次启动幂等执行 |

## 文件说明

| 文件 | 说明 |
| --- | --- |
| `docker-compose.yml` | Compose 编排文件(单容器,全部数据使用宿主机本地目录映射,含 build 配置) |
| `Dockerfile` | 优化镜像构建文件(amd64/arm64 通用) |
| `entrypoint.sh` | 启动包装脚本:探测环境 → 启动数据库 → 等待 OPEN → 执行初始化 → 输出 ready |
| `check-db.sql` | 数据库状态探测脚本(entrypoint 轮询用) |
| `initdb/01-create-oracle1.sql` | 预置用户 oracle1 的幂等初始化 SQL |
| `build.sh` | 多架构构建脚本(amd64/arm64) |
| `.env.example` | 环境变量模板,复制为 `.env` 后使用 |
| `volumes/oradata/` | 数据文件目录 → 容器内 `/opt/oracle/app/oradata/orcl` |
| `volumes/fra/` | 快速恢复区(FRA)目录 → 容器内 `/opt/oracle/app/fast_recovery_area/orcl` |
| `volumes/dump/` | Data Pump(`expdp`/`impdp`)导入导出目录 → 容器内 `/opt/oracle/dpdump` |

> 本服务**不使用 Docker 具名卷**,所有数据都落在服务目录的 `./volumes/` 下,统一管理、便于备份与迁移。
> `docker compose down` 不会影响这些目录;删除 `volumes/` 目录才会真正丢数据。

## 前置要求

- Docker Engine(含 Compose v2 插件与 buildx)。
- 内存:建议至少 2~4GB;磁盘:建议预留 15GB 以上。
- 宿主机端口 `1522` 未被占用(可在 `.env` 中通过 `ORACLE_PORT` 修改)。
- **arm64 宿主机(如 Apple Silicon)**:Oracle 11g 只有 x86-64 二进制,arm64 镜像通过
  qemu/Rosetta 模拟运行,启动更慢、性能打折,仅供开发测试。

## 快速开始

```bash
cd oracle/11g

# 1. 准备环境变量与数据目录
cp .env.example .env
mkdir -p volumes/oradata volumes/fra volumes/dump

# 2. 修正目录属主(容器内以 oracle 用户运行,需对数据目录有写权限)
#    先查镜像内 oracle 用户的 UID/GID,常见为 500:500
docker run --rm --entrypoint id yycx/oracle11:11.2.0.4 oracle
sudo chown -R 500:500 volumes/oradata volumes/fra
sudo chmod -R 775 volumes/oradata volumes/fra

# 3. 构建优化镜像并启动(首次启动需要数分钟完成数据库初始化)
docker compose up -d --build

# 4. 观察初始化日志,出现 "Database ready to use. Enjoy ;)" 即表示启动成功
docker logs -f oracle-11g
```

也可用构建脚本单独构建镜像:

```bash
./build.sh                          # 本机构建 → oracle-11g:1.0.0
PUSH=1 ./build.sh myrepo/oracle-11g:1.0.0      # 双架构(amd64+arm64)构建并推送
```

> 目录属主不对时,数据库会因无法写入数据文件而启动失败,日志中通常出现 `ORA-27072` / `ORA-01102` 之类的报错。

## 连接信息

| 参数 | 值 |
| --- | --- |
| 主机 | `localhost`(或服务器 IP) |
| 端口 | `1522`(容器内 1521,可在 `.env` 中修改) |
| SID / Service Name | `orcl` |
| 业务用户(推荐) | `oracle1` / `oracle1`(拥有增删改查、建表等全权限) |
| 管理员 | `system`(密码以镜像为准,可用 `docker logs oracle-11g` 查看;常见为 `oracle` / `install` / `123456`) |

```bash
# 用业务用户连接(开箱即用)
docker exec -it oracle-11g bash
su - oracle
sqlplus oracle1/oracle1
```

JDBC 连接串(业务用户):

```
jdbc:oracle:thin:@localhost:1522:orcl
```

> 若宿主机 `1522` 未修改,连接串中的端口即为 `1522`。

## 上手即用:用 oracle1 建表

`oracle1` 拥有 DBA 权限且与 `system` 的表完全隔离,登录后即可建表:

```sql
CREATE TABLE T_USER (
  ID          NUMBER(10) PRIMARY KEY,
  USER_NAME   VARCHAR2(100) NOT NULL,
  REMARK      VARCHAR2(500),
  CREATED_AT  DATE DEFAULT SYSDATE,
  STATUS      NUMBER(1) DEFAULT 1
);

INSERT INTO T_USER (USER_NAME, REMARK) VALUES ('张三', '第一条测试记录');
INSERT INTO T_USER (USER_NAME, REMARK) VALUES ('李四', '第二条测试记录');
COMMIT;

SELECT * FROM T_USER;
```

确认业务表都在自己的 schema 下:

```sql
SELECT owner, table_name FROM dba_tables WHERE owner = 'ORACLE1';
SELECT owner, COUNT(*) FROM dba_objects WHERE object_type = 'TABLE' GROUP BY owner;
```

---

## 镜像构建说明(Dockerfile)

- base 为 `yycx/oracle11:11.2.0.4`(仅提供 amd64),arm64 镜像在 qemu/Rosetta 模拟下运行。
- `Dockerfile` 中 `FROM --platform=linux/amd64` 固定 base 架构,保证双架构构建可复现。
- `entrypoint.sh` 的启动策略:
  1. 动态探测 `ORACLE_HOME`(先读 oracle 用户 profile,失败则扫描文件系统)与 `ORACLE_SID`(读 `/etc/oratab`);
  2. 优先复用 base 镜像自带的启动脚本(探测常见路径),找不到则手动 `lsnrctl start` + `startup`;
  3. 轮询 `v$instance.status` 直到 `OPEN`(最长约 13 分钟,超时退出便于发现问题);
  4. 依次执行 `/docker-entrypoint-initdb.d/*.sql`(幂等);
  5. 输出 `Database ready to use. Enjoy ;)` 后常驻前台。

## 自定义初始化脚本

把 SQL 放进 `volumes/initdb/` 并在 compose 的 `volumes` 中增加挂载
`./volumes/initdb:/docker-entrypoint-initdb.d`,即可在每次启动时自动执行(幂等)。

---

## 初始化数据库配置(进阶)

> **核心建议:不要用 `system` / `sys` 用户直接建业务表。**
>
> `sys` / `system` 是 Oracle 系统账号,对象存放在 `SYS` / `SYSTEM` schema 下。直接用系统账号建表会导致:
>
> - 业务表与系统表混在一起,无法区分系统对象和自己的数据;
> - 系统账号权限过大,误操作 `DROP TABLE` / `TRUNCATE` 可能损坏系统表,导致实例无法启动;
> - 权限无法按业务回收,也无法单独备份、迁移业务数据。
>
> 优化镜像已预置 `oracle1`(DBA 权限)解决上述问题;如需更多业务用户,可参考下文手动创建。

### 第 1 步:以 SYSDBA 身份连接

```bash
docker exec -it oracle-11g bash
su - oracle
sqlplus / as sysdba
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

先确认数据文件目录(以实际查询结果为准):

```sql
SELECT name FROM v$datafile;
-- 例:/opt/oracle/app/oradata/orcl/system01.dbf
```

创建业务表空间:

```sql
CREATE SMALLFILE TABLESPACE APP_TS
  DATAFILE '/opt/oracle/app/oradata/orcl/app_ts1.dbf'
  SIZE 100M
  AUTOEXTEND ON NEXT 50M
  MAXSIZE 1G
  LOGGING
  EXTENT MANAGEMENT LOCAL
  SEGMENT SPACE MANAGEMENT AUTO;
```

修改新用户的默认表空间:

```sql
ALTER USER appdba DEFAULT TABLESPACE APP_TS QUOTA UNLIMITED ON APP_TS;
```

> 新建的数据文件必须落在已挂载的目录内(`./volumes/oradata` → `/opt/oracle/app/oradata/orcl`),
> 否则容器重建后数据会丢失。确认:

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

如镜像未预置 `DATA_PUMP_DIR`(或指向的不是挂载目录),手动创建:

```sql
CREATE OR REPLACE DIRECTORY DATA_PUMP_DIR AS '/opt/oracle/dpdump';
GRANT READ, WRITE ON DIRECTORY DATA_PUMP_DIR TO ORACLE1;
```

---

## 密码与账号维护

### 修改 system / sys / oracle1 密码

```sql
ALTER USER SYSTEM IDENTIFIED BY "YourStrong#Passw0rd";
ALTER USER SYS IDENTIFIED BY "YourStrong#Passw0rd";
ALTER USER ORACLE1 IDENTIFIED BY "YourStrong#Passw0rd";
```

### 解锁并修改 SCOTT 账号

```sql
ALTER USER SCOTT ACCOUNT UNLOCK;
ALTER USER SCOTT IDENTIFIED BY "Scott#Passw0rd";
```

### 密码永不过期 / 取消登录失败锁定

优化镜像启动时会自动执行以下语句;旧数据如有需要也可手动执行:

```sql
ALTER PROFILE DEFAULT LIMIT PASSWORD_LIFE_TIME UNLIMITED;
ALTER PROFILE DEFAULT LIMIT FAILED_LOGIN_ATTEMPTS UNLIMITED;
```

### 忘记密码怎么办

使用容器内的操作系统认证进入(不需要数据库密码):

```bash
docker exec -it oracle-11g bash
su - oracle
sqlplus / as sysdba
```

然后执行 `ALTER USER ... IDENTIFIED BY ...` 重置。

---

## 常用运维命令

```bash
# 查看状态
docker compose ps
docker logs -f oracle-11g

# 停止(数据保留)
docker compose down

# 重启
docker compose restart

# 重新构建镜像(修改 Dockerfile/entrypoint/initdb 后)
docker compose build

# 备份(逻辑备份,导出到挂载的 dump 目录)
docker exec -it oracle-11g expdp oracle1/oracle1 \
  DIRECTORY=DATA_PUMP_DIR DUMPFILE=backup.dmp FULL=y

# 导入
docker exec -it oracle-11g impdp oracle1/oracle1 \
  DIRECTORY=DATA_PUMP_DIR DUMPFILE=backup.dmp FULL=y LOGFILE=imp.log

# 查看数据目录大小
du -sh volumes/*
```

物理备份(停库后直接打包数据目录):

```bash
docker compose down
tar czf ../oracle-11g-oradata-$(date +%F).tar.gz volumes/oradata volumes/fra
docker compose up -d
```

---

## 常见问题

| 现象 | 原因与处理 |
| --- | --- |
| 构建时拉取 base 镜像很慢 / 中断 | 镜像约 7.35GB,可按 `.env.example` 注释在 Dockerfile 中临时改用华为云镜像仓库地址 |
| 启动很慢 / 一直不 ready | 首次初始化需要数分钟(arm64 模拟下更久),用 `docker logs -f` 观察;entrypoint 超时会显式报错 |
| 容器反复重启 | 多为内存不足,宿主机至少留 2~4GB 给容器;或端口冲突 |
| 端口冲突 | 修改 `.env` 中的 `ORACLE_PORT`(例如 `1523`) |
| `ORA-01017` 用户名/密码错误 | 用 `su - oracle && sqlplus / as sysdba` 进入后重置密码 |
| `ORA-28001` 密码过期 | 执行上文「密码策略」放开 `PASSWORD_LIFE_TIME` |
| 重启容器后数据丢失 | 确认 `./volumes/oradata` 等目录仍在,且属主与容器内 `oracle` 用户一致 |
| 数据库启动失败(`ORA-27072` / `ORA-01102`) | 数据目录属主不对,按「快速开始」第 2 步 `chown` 后重启 |
| arm64 上启动特别慢 | 属正常现象:Oracle 11g 无 ARM 原生二进制,在 qemu/Rosetta 模拟下运行,仅供开发测试 |

---

## 参考

- [yycx/oracle11](https://hub.docker.com/r/yycx/oracle11)
- [Oracle Database 11g 官方文档](https://docs.oracle.com/en/database/112/e10764/index.htm)
- [使用 Docker Compose 快速部署 Oracle 11G 与 RustFS](https://blog.csdn.net/weixin_62018471/article/details/160839074)

# Oracle 11g / 23ai 预置镜像部署

同一目录提供两套等价的 Oracle 部署，预置内容完全一致（用户 `dev`/`dev@1234`、表空间 `TS_DEV`、
临时表空间 `TS_DEV_TMP`、样例表 `DEV.T_DEV_EXAMPLE`），按需二选一启动：

| 文件 | 数据库 | 基础镜像 | 架构 | SID / Service Name | 端口默认 |
| --- | --- | --- | --- | --- | --- |
| `docker-compose.11g.yml` | Oracle 11g XE 11.2 | `oracleinanutshell/oracle-xe-11g` | **仅 amd64** | `XE` / `XE` | `1522` |
| `docker-compose.23ai.yml` | Oracle Database 23ai Free | `gvenzl/oracle-free:23-slim` | **amd64 + arm64 原生** | `FREE` / `FREEPDB1` | `1521` |

> ⚠️ Oracle 11g 属遗留版本且无 ARM 二进制；23ai Free 是 Oracle 官方免费版本（与 Oracle 19/21 同源），
> 23.5 起原生支持 ARM。两者均为社区/官方免费镜像，仅限开发、测试与学习使用。

## 文件说明

| 文件 | 说明 |
| --- | --- |
| `docker-compose.11g.yml` | 11g 编排文件（含 seed 服务：首次启动把镜像内预建库复制到 `./volumes/`） |
| `docker-compose.23ai.yml` | 23ai 编排文件 |
| `Dockerfile.11g` | 11g 预置镜像（内嵌 entrypoint 与初始化 SQL） |
| `Dockerfile.23ai` | 23ai 预置镜像（内嵌初始化 SQL，经 `/container-entrypoint-startdb.d` 每次启动幂等执行） |
| `.env.example` | 环境变量模板，复制为 `.env` 后使用 |

数据一律落在服务目录 `./volumes/` 下（`oradata`、`fra`），`docker compose down` 不丢数据，
删除 `volumes/` 才会真正重置（下次启动会重新 seed/建库并重建预置对象）。

## 预置内容（两个版本一致）

- 用户 `DEV`（密码 `dev@1234`），默认表空间 `TS_DEV`，配额不限，授予 `CONNECT`/`RESOURCE`/`DBA`
- 表空间 `TS_DEV`（200M 自动扩展）、临时表空间 `TS_DEV_TMP`（50M 自动扩展）
- 样例表 `DEV.T_DEV_EXAMPLE`（含一条样例数据）
- 密码策略放开（永不过期、登录失败不锁定）
- 全部幂等：重复启动不报错；`DEV` 密码被改动会在下次启动重置回 `dev@1234`

## 快速开始

```bash
cd oracle/11g
cp .env.example .env

# 二选一启动
docker compose -f docker-compose.23ai.yml up -d --build   # 推荐:amd64+arm64
docker compose -f docker-compose.11g.yml up -d --build    # 仅 amd64

# 观察日志,出现 "Database ready to use. Enjoy ;)" 即就绪
docker logs -f oracle-23ai        # 或 oracle-11g
```

Linux 宿主机首次启动 23ai 前，需把数据目录属主改为容器内 oracle 用户（uid 54321）：

```bash
mkdir -p volumes/oradata && sudo chown -R 54321:54321 volumes/oradata
```

11g 无需 chown：seed 服务在容器内以 root 复制文件，属主与镜像保持一致。

## 连接信息

| 参数 | 11g | 23ai |
| --- | --- | --- |
| 主机 / 端口 | `localhost:1522` | `localhost:1521` |
| SID | `XE` | `FREE`（JDBC 也可用 service `XE`/`FREE`） |
| Service Name | `XE` | `FREEPDB1` |
| 业务用户 | `dev` / `dev@1234` | `dev` / `dev@1234` |
| 管理员 | `system` / `oracle` | `system` / `${ORACLE_SYS_PASSWORD}`（默认 `SysOracle123`） |

```
jdbc:oracle:thin:@localhost:1522:XE        # 11g
jdbc:oracle:thin:@localhost:1521/FREEPDB1  # 23ai
```

sqlplus 验证：

```bash
# 11g
docker exec -it oracle-11g sqlplus dev/'"dev@1234"'@localhost:1522/XE
# 23ai(容器内)
docker exec -it oracle-23ai sqlplus dev/'"dev@1234"'@localhost:1521/FREEPDB1

SELECT table_name FROM user_tables;
CREATE TABLE t_test (id NUMBER(10) PRIMARY KEY, name VARCHAR2(100));
INSERT INTO t_test VALUES (1, '中文测试');
COMMIT;
SELECT * FROM t_test;
```

## Navicat thick（OCI）模式连接

两个版本都支持 thick 模式，注意客户端版本：

- 11g：Oracle Instant Client 19c 即可；
- 23ai：必须用 **19c 或 23ai** Instant Client，Navicat 自带的 `instantclient_11_2` 过旧，
  会报 `ORA-28040: No matching authentication protocol`；
- Apple Silicon 可用 macOS ARM64 原生 Instant Client，无需 Rosetta。

设置：Navicat → 工具 → 选项 → 环境 → OCI library 指向 Instant Client 的 `oci.dll`/`libclntsh.dylib`
（Windows / Linux / macOS 路径各自对应），重启 Navicat 后连接方式与 thin 模式相同。

## 常用运维命令

```bash
docker compose -f docker-compose.23ai.yml ps
docker compose -f docker-compose.23ai.yml down       # 数据保留
docker compose -f docker-compose.23ai.yml restart
docker compose -f docker-compose.23ai.yml build      # 改 Dockerfile 后重建

# 完全重置(重新建库/seed)
docker compose -f docker-compose.23ai.yml down
sudo rm -rf volumes/ && sudo chown -R 54321:54321 volumes/oradata 2>/dev/null || true
docker compose -f docker-compose.23ai.yml up -d
```

## 常见问题

| 现象 | 处理 |
| --- | --- |
| Navicat 报 `ORA-28040` | thick 客户端太旧，改用 19c/23ai Instant Client（见上文） |
| 中文乱码 / 问号 | 客户端 `NLS_LANG` 设为 `AMERICAN_AMERICA.AL32UTF8`；11g 容器已默认设置 |
| `ORA-12514` / `ORA-12528` | 库尚未 OPEN，`docker logs -f` 等待就绪提示 |
| 11g 首次启动卡住 | seed 服务正在复制预建库（约数百 MB），`docker compose -f docker-compose.11g.yml logs oracle-seed` 查看 |
| 23ai 启动失败且日志提示权限 | Linux 上未 chown 数据目录（uid 54321），见快速开始 |
| 端口冲突 | 修改 `.env` 中 `ORACLE_11G_PORT` / `ORACLE_23AI_PORT` |
| 忘记密码 | 11g: `docker exec -it oracle-11g sqlplus / as sysdba`；23ai: `docker exec -it oracle-23ai sqlplus sys/<ORACLE_SYS_PASSWORD>@FREE as sysdba`，然后 `ALTER USER ... IDENTIFIED BY ...` |

## 最终保留单一文件

验证完两个变体后，把选中的 compose 与对应 Dockerfile 留下并改名：

```bash
# 例:保留 23ai
mv docker-compose.23ai.yml docker-compose.yml
mv Dockerfile.23ai Dockerfile
rm docker-compose.11g.yml Dockerfile.11g
# .env 中相应变量前缀同步精简后即可
```

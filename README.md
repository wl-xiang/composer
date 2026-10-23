# docker-compose 服务部署集(Monorepo)

本仓库是一个 **monorepo**,集中存放多个服务的 **Docker Compose** 部署配置。
每个服务独占一个目录,目录内包含编排文件、环境变量模板与说明文档;仓库根目录提供统一的
目录规范、访问入口与 CI 打包 Action。

> 本仓库原本只用于部署 Gitea,现重构为 monorepo,以便后续新增 Redis、MySQL、Nginx 等服务时
> **不需要再单独建仓**。

## 服务清单

| 服务 | 目录 | Action Choice | 默认端口 | 默认账号 | 说明 |
| --- | --- | --- | --- | --- | --- |
| Gitea + PostgreSQL | [`gitea/`](gitea/) | `gitea` | `44180`(Web)/`222`(SSH) | 首次访问走安装向导 | [Gitea 官方文档](https://docs.gitea.com/installation/install-with-docker/) |
| Oracle 11g XE | [`oracle/11g-xe/`](oracle/11g-xe/) | `oracle-11g-xe` | `1521` | `system` / `oracle` | 社区镜像,仅供开发测试 |
| Oracle 11g EE | [`oracle/11g/`](oracle/11g/) | `oracle-11g` | `1522` | `system`(密码以镜像为准) | 社区镜像,仅供开发测试 |

每个服务的完整使用说明(启动、连接、初始化、备份、常见问题)请查看其目录下的 `README.md`。

## 目录结构

```
.
├── README.md                    # 本文件:服务清单、目录规范、新增服务指引
├── .gitignore
├── .github/
│   └── workflows/
│       └── pack.yml             # 打包 Action:下拉选择服务 → 生成压缩包
├── gitea/                       # 服务:目录名即服务名
│   ├── README.md
│   ├── docker-compose.yml
│   ├── .env.example
│   └── volumes/                 # 运行时数据(自动生成,不入库)
│       ├── gitea/               # → 容器 /data
│       └── postgres/            # → 容器 /var/lib/postgresql
└── oracle/
    ├── 11g-xe/                  # 服务:子目录名即服务名
    │   ├── README.md
    │   ├── docker-compose.yml
    │   ├── .env.example
    │   └── volumes/             # 运行时数据(自动生成,不入库)
    │       ├── oradata/         # → 容器 /u01/app/oracle/oradata
    │       └── dump/            # → 容器 /u01/app/oracle/dpdump
    └── 11g/
        ├── README.md
        ├── docker-compose.yml
        ├── .env.example
        └── volumes/             # 运行时数据(自动生成,不入库)
            ├── oradata/         # → 容器 /opt/oracle/app/oradata/orcl
            ├── fra/             # → 容器 /opt/oracle/app/fast_recovery_area/orcl
            └── dump/            # → 容器 /opt/oracle/dpdump
```

## 通用约定

1. **一个服务一个目录**:目录内必须包含 `docker-compose.yml`、`.env.example`、`README.md` 三个文件。
2. **目录命名**:
   - 顶层目录名即服务名(如 `gitea`);
   - 需要归类时使用「类别/服务名」两级结构(如 `oracle/11g`),**最多两级**。
3. **数据一律使用宿主机本地目录映射(强制规则)**:
   - 所有 `docker-compose.yml` 中用于**持久化数据与日志**的 `volumes` **必须**写成
     `./volumes/xxx:容器内路径` 的本地目录映射,**禁止使用 Docker 具名卷**
     (即禁止在 compose 顶层声明 `volumes:` 并在服务中引用卷名);
   - 每个服务的数据目录统一放在**该服务目录下**的 `volumes/` 中,按用途分子目录,
     例如 `gitea/volumes/gitea`、`gitea/volumes/postgres`、`oracle/11g/volumes/oradata`;
   - 数据目录名建议与用途对应:`oradata`(数据文件)、`fra`(快速恢复区)、`dump`(导入导出)、`data`(通用数据)、`logs`(日志);
   - 该目录由根目录 `.gitignore` 忽略,**不得提交**到仓库;
   - 目录映射路径需通过环境变量注入并带默认值,例如 `${REDIS_DATA_DIR:-./volumes/data}:/data`,
     方便使用者按需调整;
   - **例外**:时区等系统文件的只读挂载(如 `/etc/localtime:/etc/localtime:ro`)不属于数据卷,可原样保留。
4. **密钥不入库**:真实配置写在服务目录的 `.env`(已被忽略),仓库中只保留 `.env.example` 模板。
5. **compose 文件必须支持环境变量覆盖**:镜像、端口、数据目录等通过 `${VAR:-default}` 形式注入。
6. **命令在服务目录内执行**:所有 `docker compose` 命令都在对应服务目录下运行(Compose 以文件所在目录为项目根)。
7. **子目录 README 至少包含**:用途说明、镜像与许可提示、前置要求、启动步骤、连接信息、常用运维命令、常见问题。

---

## 如何新增一个服务

以新增 `redis` 服务为例,完整步骤如下:

### 1. 创建服务目录

```bash
mkdir -p redis
```

(若需归类,例如 `cache/redis`,则创建 `cache/redis`,深度最多两级。)

### 2. 编写 `redis/docker-compose.yml`

```yaml
name: redis

services:
  redis:
    image: ${REDIS_IMAGE:-redis:7-alpine}
    container_name: ${REDIS_CONTAINER_NAME:-redis}
    restart: unless-stopped
    ports:
      - "${REDIS_PORT:-6379}:6379"
    volumes:
      # 本地目录映射,统一放在服务目录的 ./volumes/ 下
      - ${REDIS_DATA_DIR:-./volumes/data}:/data
      - ${REDIS_LOG_DIR:-./volumes/logs}:/var/log/redis
```

要求:
- 顶层写 `name:`;
- 敏感信息通过环境变量注入;
- **数据必须使用 `./volumes/xxx` 本地目录映射,禁止使用 Docker 具名卷**;
- 不要在 compose 顶层声明 `volumes:`(具名卷)。

### 3. 编写 `redis/.env.example`

列出所有可调参数,每项附中文注释,便于使用者复制为 `.env` 后修改。

### 4. 编写 `redis/README.md`

说明用途、镜像来源与许可、前置要求(端口/内存/磁盘)、启动步骤、连接方式、默认账号密码、
常用运维命令、数据备份与常见问题。**若服务需要初始化配置(建库、建用户、建表等),
必须把初始化步骤写清楚,并给出「建议用户自行创建独立账号」之类的最佳实践。**

### 5. 在根目录 `README.md` 的「服务清单」中登记一行

| 服务 | 目录 | Action Choice | 默认端口 | 默认账号 | 说明 |
| --- | --- | --- | --- | --- | --- |
| Redis | [`redis/`](redis/) | `redis` | `6379` | 无 | 内存数据库 |

### 6. 在 Action 中新增 choice

编辑 [`.github/workflows/pack.yml`](.github/workflows/pack.yml),在 `options` 中追加一个选项:

```yaml
        options:
          - gitea
          - oracle-11g-xe
          - oracle-11g
          - redis        # ← 新增
```

**命名规则:choice 名称 = 服务目录路径中的 `/` 替换为 `-`。**

| 服务目录 | Action Choice |
| --- | --- |
| `gitea` | `gitea` |
| `oracle/11g-xe` | `oracle-11g-xe` |
| `oracle/11g` | `oracle-11g` |
| `cache/redis` | `cache-redis` |

打包 Action 会按该规则在仓库中查找对应目录,找不到(或匹配到多个目录)时会直接报错,
因此**新增服务时务必同步新增 choice,并保证 choice 名称与目录路径一致**。

### 7. 自检清单

- [ ] 服务目录下三个文件齐全:`docker-compose.yml`、`.env.example`、`README.md`
- [ ] 所有 `volumes` 均为 `./volumes/xxx` 本地目录映射,compose 顶层**没有**声明具名卷
- [ ] `docker compose config` 可通过(compose 文件语法正确、变量默认值齐全)
- [ ] 服务 README 含启动/连接/运维/常见问题
- [ ] 根目录 README 的「服务清单」已登记
- [ ] `.github/workflows/pack.yml` 的 `options` 已新增对应 choice

---

## 打包 Action(Pack Service)

文件:[`.github/workflows/pack.yml`](.github/workflows/pack.yml)

### 使用方式

1. 打开仓库的 **Actions** 标签页,选择 **Pack Service**;
2. 点击 **Run workflow**,在下拉框中选择要打包的服务;
3. 等待运行结束,在运行详情页底部下载 `artifact`(形如 `oracle-11g.tar.gz`)。

### 行为说明

- 输入 `service` 为 `type: choice` 的下拉菜单,选项即「服务清单」中的 Action Choice;
- 打包内容为该服务目录的完整内容,**自动排除**运行时数据(`volumes/`)与含真实密码的 `.env`;
- 打包结果以 artifact 形式上传,保留 14 天。

## 注意事项

- Oracle 11g 两个服务使用的都是**社区镜像**,仅限开发、测试与学习使用;
  生产环境请使用受支持的 Oracle 版本(19c 及以上)、官方镜像并自行解决授权。
- 同一台机器上部署多个服务时,请确认端口不冲突(可在各自 `.env` 中修改)。
- 各服务数据目录互相独立,备份时请分别处理。

# Gitea Docker Compose 部署

基于 [Gitea 官方文档](https://docs.gitea.com/installation/install-with-docker/#postgresql-database)的 **Gitea + PostgreSQL** Docker Compose 部署方案。

## 文件说明

| 文件 | 说明 |
| --- | --- |
| `docker-compose.yml` | Compose 编排文件(Gitea + PostgreSQL) |
| `.env.example` | 环境变量模板,复制为 `.env` 后使用 |
| `volumes/gitea/` | Gitea 持久化数据(仓库、配置 `app.ini` 等,运行后生成) |
| `volumes/postgres/` | PostgreSQL 持久化数据(运行后生成) |

## 前置要求

- Docker Engine(含 Compose v2 插件),安装参考 [Docker 官方文档](https://docs.docker.com/compose/install/)。

## 快速开始

1. 准备环境变量:

   ```bash
   cp .env.example .env
   # 编辑 .env,至少修改 POSTGRES_PASSWORD 为强密码
   ```

2. 启动服务(后台运行):

   ```bash
   docker compose up -d
   ```

3. 查看状态与日志:

   ```bash
   docker compose ps
   docker compose logs -f
   ```

4. 浏览器访问 `http://<服务器IP>:44180`,按安装向导完成初始化。数据库连接已通过环境变量(`GITEA__database__*`)预配置;如需手动填写,数据库主机必须填 `db`。

5. 通过 SSH 克隆仓库(端口默认映射为 `222`):

   ```bash
   git clone ssh://git@<服务器IP>:222/<用户名>/<仓库>.git
   ```

## 常用命令

```bash
# 停止(数据卷仍保留)
docker compose down

# 升级到新版本:修改 .env 中的 GITEA_VERSION / POSTGRES_VERSION 后执行
docker compose pull
docker compose up -d
```

## 数据持久化与备份

- Gitea 数据挂载在 `./volumes/gitea`(容器内 `/data`),配置文件位于 `./volumes/gitea/gitea/conf/app.ini`。
- PostgreSQL 数据挂载在 `./volumes/postgres`。
- 备份示例:

  ```bash
  # 停止写入后直接打包数据目录
  tar czf gitea-backup-$(date +%F).tar.gz volumes

  # 或使用 Gitea 内置备份命令
  docker compose exec -u git server gitea dump
  ```

## 注意事项

- **数据目录权限**:使用宿主机目录(host volume)时,`./volumes/gitea` 的属主 UID/GID 需与 `.env` 中的 `USER_UID`/`USER_GID` 一致,否则容器可能无法启动:

  ```bash
  sudo chown -R 1000:1000 volumes/gitea
  ```

- **跨平台**:容器挂载了 `/etc/timezone` 和 `/etc/localtime` 以同步宿主机时区,这两项仅适用于 Linux;在 macOS/Windows 上部署请注释掉 `docker-compose.yml` 中对应的两行。
- **修改数据库密码**:仅在首次初始化(空的 `./volumes/postgres` 目录)前修改有效;已有数据后需同步修改 PostgreSQL 内用户密码,并更新 `app.ini` 或 `.env` 中的对应值。
- **rootful / rootless 镜像不兼容**:本仓库使用默认 rootful 镜像(`docker.gitea.com/gitea`),请勿直接将 `image` 改为 rootless 镜像。

## 参考

- [Installation with Docker - Gitea Docs](https://docs.gitea.com/installation/install-with-docker/)
- [Gitea 官方文档首页](https://docs.gitea.com/)

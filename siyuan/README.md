# SiYuan(思源笔记) Docker Compose 部署

基于 [SiYuan 官方仓库](https://github.com/siyuan-note/siyuan) 的 **b3log/siyuan** 镜像 Docker Compose 部署方案。

> 本目录是 [monorepo](../README.md) 中的一个服务目录,Action Choice 为 `siyuan`。
> 下列所有命令都在 **本目录(`siyuan/`)** 下执行。

## 文件说明

| 文件 | 说明 |
| --- | --- |
| `docker-compose.yml` | Compose 编排文件(SiYuan 单服务) |
| `.env.example` | 环境变量模板,复制为 `.env` 后使用 |
| `volumes/workspace/` | SiYuan 工作区持久化数据(笔记本、资源文件、配置等,运行后生成) |

## 前置要求

- Docker Engine(含 Compose v2 插件),安装参考 [Docker 官方文档](https://docs.docker.com/compose/install/)。
- 宿主机端口 `6806`(可在 `.env` 中修改)未被占用。

## 快速开始

1. 准备环境变量:

   ```bash
   cp .env.example .env
   # 编辑 .env,务必修改 SIYUAN_ACCESS_AUTH_CODE 为强密码
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

4. 浏览器访问 `http://<服务器IP>:6806`,输入 `.env` 中配置的访问授权码(`SIYUAN_ACCESS_AUTH_CODE`)即可进入。

## 常用命令

```bash
# 停止(数据卷仍保留)
docker compose down

# 升级到新版本:修改 .env 中的 SIYUAN_VERSION 后执行
docker compose pull
docker compose up -d
```

## 数据持久化与备份

- 工作区数据挂载在 `./volumes/workspace`(容器内 `/siyuan/workspace`),包含笔记本、资源文件与配置,升级/重建容器不丢失。
- 备份示例(停止写入后直接打包数据目录):

  ```bash
  docker compose down
  tar czf siyuan-backup-$(date +%F).tar.gz volumes
  docker compose up -d
  ```

- 也可使用 SiYuan 内置的「数据历史/快照」与「导出 .sy 文档」功能做逻辑备份,便于跨平台恢复。

## 注意事项

- **`serve` 子命令不能省**:镜像 entrypoint 规定,通过 `command:` 传参时必须带上 `serve` 子命令,否则用户参数会整体覆盖 CMD 导致服务不启动。
- **数据目录权限**:镜像 entrypoint 会以 root 启动并自动把工作区 `chown` 为 `PUID:PGID`(默认 `1000:1000`)后降权运行,宿主机目录无需手动授权;如需对齐宿主机用户,可修改 `.env` 中的 `SIYUAN_PUID`/`SIYUAN_PGID`(改动后首次启动会重新 chown)。
- **修改访问授权码**:直接修改 `.env` 中的 `SIYUAN_ACCESS_AUTH_CODE` 后执行 `docker compose up -d` 重建容器即可生效。
- **固定镜像版本**:`latest` 跟随上游自动更新,建议在 `.env` 中将 `SIYUAN_VERSION` 固定为具体版本号,避免不可预期的升级。
- **公网部署**:务必使用强授权码;更安全的做法是仅在反向代理(HTTPS)后暴露服务,并收紧 `6806` 端口的访问来源。

## 参考

- [SiYuan 官方仓库](https://github.com/siyuan-note/siyuan)
- [b3log/siyuan - Docker Hub](https://hub.docker.com/r/b3log/siyuan)

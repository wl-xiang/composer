# RustFS Docker Compose 部署

基于 [RustFS 官方示例](https://github.com/rustfs/rustfs/blob/main/docker-compose-simple.yml)的
**单机多盘** Docker Compose 部署方案。RustFS 是一款 S3 兼容的高性能开源分布式对象存储,
采用 Apache-2.0 许可证。

> 本目录是 [monorepo](../README.md) 中的一个服务目录,Action Choice 为 `rustfs`。
> 下列所有命令都在 **本目录(`rustfs/`)** 下执行。

## 与官方示例的差异(bind 绑定)

官方示例使用 Docker 具名卷(named volume);本目录按 monorepo 约定,把**所有卷统一改成了
宿主机目录 bind 绑定**(`./volumes/xxx:容器内路径`)。与具名卷相比,bind 绑定意味着:

- 数据目录完全由你自己管理,路径直观,备份/迁移就是拷贝目录;
- **`rm -rf` 会直接删掉对象存储数据**,没有具名卷的隔离保护,操作时务必小心;
- 宿主机目录的属主/权限会直接影响容器读写,RustFS 容器内以 **uid=10001 / gid=10001** 运行,
  因此**启动前必须准备好属主可写的绑定目录**,详见下文。

## 文件说明

| 文件/目录 | 说明 |
| --- | --- |
| `docker-compose.yml` | Compose 编排文件(RustFS + 权限修复辅助容器) |
| `.env.example` | 环境变量模板,复制为 `.env` 后使用 |
| `volumes/rustfs0..3/` | 4 个数据盘目录(需提前创建,运行后写入数据) |
| `volumes/logs/` | 日志目录(需提前创建,运行后写入日志) |

## 前置要求

- Docker Engine(含 Compose v2 插件),安装参考 [Docker 官方文档](https://docs.docker.com/compose/install/)。
- 磁盘空间:按对象存储的实际容量规划。

## ⚠️ 首次启动前:提前创建 bind 绑定目录(必做)

所有映射均为 bind 绑定,**启动前请先在本目录创建好对应的文件夹**:

```bash
mkdir -p ./volumes/rustfs{0,1,2,3} ./volumes/logs
```

- 若不提前创建:Linux 下 Docker 会自动创建,但**属主是 root**,RustFS(10001:10001)无法写入;
  本目录默认保留了 `volume-permission-helper` 辅助容器,每次 `up` 时会自动把目录
  `chown` 成 `10001:10001`。
- **macOS Docker Desktop 注意**:bind mount 的权限模型不同,容器内 `chown` 不会生效,
  helper 会失效,必须采用下面的「方案B」。
- 若在 `.env` 中自定义了 `RUSTFS_*_DIR` 路径,请按实际路径创建对应目录。

### 目录权限的两个方案

RustFS 容器内运行用户为 `10001:10001`,宿主机绑定目录必须对该用户可写,二选一:

- **方案A(默认,推荐懒人):保留 permission helper**
  保持 `docker-compose.yml` 现状即可,helper 容器每次 `up` 时自动 `chown -R 10001:10001`。

- **方案B(生产更干净):宿主机手动授权,删掉 helper 服务**

  ```bash
  sudo chown -R 10001:10001 ./volumes/
  ```

  然后删除 `docker-compose.yml` 中的 `volume-permission-helper` 服务,以及 `rustfs`
  服务里对应的 `depends_on` 段落,避免每次 `up` 都跑一遍 chown。

  macOS 上除手动授权外,还需给 `rustfs` 服务增加与宿主机用户一致的 `user` 配置
  (执行 `id -u` / `id -g` 查看自己的 uid/gid,macOS 默认通常是 `501:20`):

  ```yaml
  services:
    rustfs:
      user: "501:20"
  ```

## 快速开始

1. 准备环境变量:

   ```bash
   cp .env.example .env
   # 编辑 .env,至少修改 RUSTFS_ACCESS_KEY / RUSTFS_SECRET_KEY
   ```

2. 创建 bind 绑定目录(见上一节,**必做**):

   ```bash
   mkdir -p ./volumes/rustfs{0,1,2,3} ./volumes/logs
   ```

3. 启动服务(后台运行):

   ```bash
   docker compose up -d
   ```

4. 查看状态与日志:

   ```bash
   docker compose ps
   docker compose logs -f
   ```

## 连接信息

| 项目 | 值 |
| --- | --- |
| S3 API | `http://<服务器IP>:9000` |
| Web 控制台 | `http://<服务器IP>:9001`(用 `.env` 中的 Access Key / Secret Key 登录) |
| 默认账号 | `rustfsadmin` / `rustfsadmin`(**仅默认值,务必在 `.env` 中修改**) |

## 常用命令

```bash
# 停止(数据目录仍保留)
docker compose down

# 升级到新版本:修改 .env 中的 RUSTFS_IMAGE 后执行
docker compose pull
docker compose up -d
```

## 数据持久化与备份

- 4 个数据盘分别绑定在 `./volumes/rustfs0` ~ `./volumes/rustfs3`(容器内 `/data/rustfs{0...3}`),
  日志绑定在 `./volumes/logs`(容器内 `/app/logs`)。
- 备份示例:

  ```bash
  # 停止写入后直接打包数据目录
  tar czf rustfs-backup-$(date +%F).tar.gz volumes
  ```

- 再次提醒:**bind 绑定目录由你全权管理**,删除目录即删除数据,请谨慎执行清理类命令。

## 常见问题

- **容器启动失败,日志报 Permission denied**:绑定目录属主不对,按「目录权限的两个方案」
  处理(方案A 由 helper 自动 chown,方案B 手动 `chown -R 10001:10001 ./volumes/`)。
- **macOS 上 helper 不生效**:mac 的 bind mount 不支持容器内 chown 修改宿主机文件 uid,
  请改用「方案B」并给 rustfs 服务配置 `user: "<uid>:<gid>"`。
- **磁盘拓扑校验失败**:`RUSTFS_VOLUMES=/data/rustfs{0...3}` 要求恰好 4 个数据目录且路径匹配,
  请确认 4 个目录都已创建;仅本地测试时可把 `.env` 中的
  `RUSTFS_UNSAFE_BYPASS_DISK_CHECK` 改为 `true` 跳过校验(生产环境禁止)。
- **修改 Access Key / Secret Key**:仅首次初始化(空的 `./volumes/` 目录)前修改有效;
  已有数据后需在控制台或 S3 API 中同步修改,再更新 `.env`。
- **启用 TLS(可选)**:将证书目录挂载到容器 `/opt/tls`,并设置环境变量
  `RUSTFS_TLS_PATH=/opt/tls`;启用后健康检查会自动切换为 HTTPS。

## 参考

- [RustFS 官方仓库](https://github.com/rustfs/rustfs)
- [docker-compose-simple.yml 官方示例](https://github.com/rustfs/rustfs/blob/main/docker-compose-simple.yml)
- [Bind mounts - Docker Docs](https://docs.docker.com/engine/storage/bind-mounts/)

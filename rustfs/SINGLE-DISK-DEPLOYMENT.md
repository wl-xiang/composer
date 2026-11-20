# 单盘部署说明(Single Node Single Disk, SNSD)

本文说明:

1. 为什么默认的「4 个数据盘」配置在**只有一块物理盘**的机器上会启动失败;
2. 如何把本项目改成**单盘单目录**部署并正常启动。

适用场景:本地开发机、测试机,以及只有一块数据盘的服务器。单盘部署**没有冗余**,
磁盘损坏即数据丢失,必须自行做好备份。

---

## 一、为什么默认 4 盘配置会启动失败

### 1. 4 个目录的用途:纠删码(EC)

默认配置里 `RUSTFS_VOLUMES=/data/rustfs{0...3}` 会把 4 个目录当作 **4 块独立数据盘**,
交给 RustFS 做 Reed-Solomon 纠删码:

- 4 个数据端点时,RustFS 自动采用 `EC:2`,即 **2 个数据分片 + 2 个校验分片**;
- 可容忍 2 个盘故障,容量效率约 50%;
- 前提是这些分片要分布在**不同物理盘(不同故障域)**上,才有真实的容错意义。

### 2. 同盘导致校验失败

如果 4 个目录都落在同一块物理盘(如 `sda`)上,它们的大设备号 `st_dev` 相同。
RustFS 启动时会检查每个数据端点的物理设备,发现全部指向同一块盘,于是拒绝启动:

```text
[FATAL] Server runtime failed: local erasure endpoints must use distinct physical disks;
detected shared devices [sda => /data/rustfs0, /data/rustfs1, /data/rustfs2, /data/rustfs3];
...
Set RUSTFS_UNSAFE_BYPASS_DISK_CHECK=true only for local testing or CI to bypass this safety check
```

容器会因此不断重启(`Restarting`)。

### 3. 为什么这个检查是合理的

纠删码的意义在于「坏一盘还能从其它盘的分片重建数据」。但 4 个目录共用一个物理盘时:

- 故障域只有一个:**这块盘一坏,4 份分片同时丢失,EC 容错实际为 0**;
- 却仍然付出约 50% 的容量开销(4 盘 EC:2),**可靠性没换来,容量还减半**;
- 只有一点并发 IO 的收益。

所以在单盘机器上保留 4 目录布局并不划算。RustFS 因此默认把这种拓扑判为不安全。

### 4. `RUSTFS_UNSAFE_BYPASS_DISK_CHECK=true` 是什么

它是官方提供的**逃生开关**,用于本地测试/CI 强行跳过上述物理盘校验。设置后 4 目录
布局能在单盘上跑起来,但如前所述**没有真实冗余**。生产环境不建议长期使用。

> 结论:只有一块物理盘时,应改用官方的单盘模式(SNSD),而不是绕过检查继续用 4 目录。

---

## 二、如何改成单盘部署

单盘模式使用**一个数据目录** `RUSTFS_VOLUMES=/data/rustfs0`,不做跨盘 EC。
官方单盘模式的参考文档:<https://docs.rustfs.com/en/installation/linux/single-node-single-disk>

### 1. 修改 `docker-compose.yml`

**(a) 数据卷变量**

```yaml
# 改前
- RUSTFS_VOLUMES=/data/rustfs{0...3}

# 改后
- RUSTFS_VOLUMES=/data/rustfs0
```

**(b) rustfs 服务的数据卷挂载**(只保留 rustfs0 与 logs)

```yaml
volumes:
  - ${RUSTFS_DATA_0_DIR:-./volumes/rustfs0}:/data/rustfs0
  - ${RUSTFS_LOGS_DIR:-./volumes/logs}:/app/logs
```

删除 `rustfs1` / `rustfs2` / `rustfs3` 三行挂载。

**(c) `volume-permission-helper` 服务的挂载与 chown**

```yaml
volumes:
  - ${RUSTFS_DATA_0_DIR:-./volumes/rustfs0}:/data/rustfs0
  - ${RUSTFS_LOGS_DIR:-./volumes/logs}:/app/logs
command: >
  sh -c "
    chown -R 10001:10001 /data/rustfs0 /app/logs &&
    echo 'Bind mount permissions fixed to 10001:10001' &&
    exit 0
  "
```

### 2. 修改 `.env`

删除多余的数据目录变量,只保留 rustfs0 与 logs,并关闭绕过开关:

```dotenv
RUSTFS_DATA_0_DIR=./volumes/rustfs0
RUSTFS_LOGS_DIR=./volumes/logs

RUSTFS_UNSAFE_BYPASS_DISK_CHECK=false
```

删除以下三行:

```dotenv
RUSTFS_DATA_1_DIR=./volumes/rustfs1
RUSTFS_DATA_2_DIR=./volumes/rustfs2
RUSTFS_DATA_3_DIR=./volumes/rustfs3
```

### 3. 清理旧的多盘格式元数据(关键)

如果之前已用 4 目录布局启动过,`./volumes/rustfs0/.rustfs.sys` 里保存的是**多盘布局的格式**。
直接切到单盘会因格式不匹配而启动失败。**首次切换前必须清掉旧格式元数据**
(里面只有系统元数据,首次部署时没有业务数据)。

安全做法(用临时 root 容器删除,避免宿主机权限问题):

```bash
docker compose down
docker run --rm -v "$PWD/volumes:/volumes" alpine \
  sh -c "rm -rf /volumes/rustfs0/.rustfs.sys"
```

> 若已存在业务数据,请先备份,不要直接删除。

### 4. 创建目录并启动

```bash
mkdir -p ./volumes/rustfs0 ./volumes/logs
docker compose config -q   # 校验配置
docker compose up -d
```

`volume-permission-helper` 会自动把目录属主修为 `10001:10001`。

### 5. 验证

```bash
docker compose ps
# STATUS 应为 Up ... (healthy)

docker compose logs --tail=20
# 应看到: Starting: /usr/bin/rustfs  /data/rustfs0

curl -fsS http://127.0.0.1:9000/health
curl -fsS http://127.0.0.1:9001/rustfs/console/health
```

访问:

- S3 API:`http://<服务器IP>:9000`
- Web 控制台:`http://<服务器IP>:9001`

---

## 三、单盘模式的重要限制

- **无冗余**:磁盘故障即数据全部丢失,必须做外部备份(如定期 `tar` 数据目录或同步到远端)。
- **不能原地加盘扩容**:官方说明单盘单节点(SNSD)部署无法通过增加端点/存储池原地扩容;
  后续想用多盘纠删码,需要**新建多盘部署,再通过 S3 迁移数据**。
- **账号仅在初始化前有效**:Access Key / Secret Key 只在数据目录为空时生效;已有数据后需
  在控制台或 S3 API 中修改。

如需冗余,应使用多块**独立物理盘**(单机多盘 SNMD)或**多节点**(MNMD),而不是在同一块盘上
创建多个目录。

---

## 四、与默认配置的差异速览

| 项目 | 默认(4 盘) | 单盘(本文) |
| --- | --- | --- |
| `RUSTFS_VOLUMES` | `/data/rustfs{0...3}` | `/data/rustfs0` |
| 数据目录 | `./volumes/rustfs0..3` | `./volumes/rustfs0` |
| 纠删码 | `EC:2`(需不同物理盘) | 无(单盘) |
| 可靠性 | 多盘时可容 2 盘故障 | 无冗余,依赖备份 |
| 容量效率 | 约 50% | 100%(扣除文件系统开销) |
| 磁盘校验 | 要求各盘不同物理设备 | 单盘天然通过 |
| 扩容 | 多盘池格式不可变,可追加池 | 不可原地扩容,需迁移 |

# RustFS 端口 49001 无法访问问题排查记录

- 日期: 2026-11-21
- 环境: Kylin Linux, 内核 4.4.131, Docker 29.5.3, Docker Compose 5.1.4
- 目录: `/home/user/deploy/rustfs/rustfs`
- 相关文件: `docker-compose.yml`(修复同样已应用到 `docker-compose.single-disk.yml`、`docker-compose.fixed-latest.yml`、`docker-compose.single-disk.fixed-latest.yml`)

## 现象

执行 `docker compose up -d` 后:

- `rustfs-server` 容器状态为 `Up (healthy)`,容器内部健康检查正常。
- 宿主机 `ss -tln` 能看到 `49001` 和 `9000` 在监听。
- 但从宿主机或局域网访问 `http://<IP>:49001` 时连接一直挂起,`curl` 超时(返回码 `000`)。
- `docker compose ps` 显示端口映射存在:
  - `0.0.0.0:49001->9001/tcp`(Console)
  - `0.0.0.0:49000->9000/tcp`(S3)

容器本身没问题,问题出在宿主机到容器之间的 Docker 网络链路。

## 排查过程

### 1. 确认服务和端口

```bash
docker compose ps
ss -tln | grep -E ':(49001|9000)\b'
curl -s --max-time 5 http://127.0.0.1:49001/rustfs/console/health
```

容器内访问正常:

```bash
docker exec rustfs-server curl -s http://127.0.0.1:9001/rustfs/console/health
# {"service":"rustfs-console","status":"ok",...}
```

说明 RustFS 进程和端口映射配置都没有问题,故障点在宿主机与容器网络之间。

### 2. 检查网络和网桥

```bash
docker network ls
ip route
ip -br addr
```

发现关键异常:

- 容器所在网络 `rustfs_rustfs-network` 的子网是 `172.30.0.0/16`。
- 对应的网桥 `br-96864a5bdca0` 状态为 `DOWN`,而且**没有网关 IP `172.30.0.1`**。
- 宿主机路由表中也没有 `172.30.0.0/16` 路由。
- 容器 veth 网卡虽然插在网桥上,但端口状态为 `disabled`。

Docker 日志中也有对应告警:

```text
level=warning msg="Bridge port not forwarding" ... veth=veth9f64c48 waitTime=200ms
```

即:容器流量出了 veth 之后,因为网桥没有配置好,数据包无法回到宿主机/外网,导致端口"在监听但无响应"。

### 3. 验证会不会复现

新建一个临时网络:

```bash
docker network create zz-test-net
```

该网络的网桥能正常拿到网关 IP,说明不是所有新网络都会失败。

再用临时 compose 工程模拟"一次创建两个网络":

```yaml
services:
  a:
    image: alpine
    command: sleep 300
    networks: [netA, netB]
networks:
  netA:
  netB:
```

结果稳定复现:**两个网络同时创建时,其中一个网桥缺失网关 IP 并处于 DOWN 状态**,另一个正常。

## 根因

`docker-compose.yml` 中存在两个网络:

1. `rustfs_rustfs-network`:RustFS 主服务显式使用的网络。
2. `rustfs_default`:由 `volume-permission-helper` 服务隐式创建(该服务没有指定网络,compose 自动给它分配 default 网络)。

Compose 启动时会**并发创建这两个网络**。在当前 Docker 版本 + 旧内核(4.4)的组合下,libnetwork 创建网桥存在竞态:其中一个网桥创建后没有完成地址/UP 配置,而 RustFS 恰好被分配到出问题的那个网络,于是出现:

- 端口已发布、`ss` 显示监听;
- 但 DNAT/docker-proxy 指向的容器网络不可达,连接超时。

## 修复方案

`volume-permission-helper` 只负责对宿主机目录执行 `chown`,完全不需要网络。因此给它加上 `network_mode: none`,让 Compose 只创建一个网络,从根源上避开并发创建竞态。

修改位置:各 compose 文件的 `volume-permission-helper` 服务。

```yaml
  volume-permission-helper:
    image: ${RUSTFS_HELPER_IMAGE:-alpine}
    # 只需要改本地目录属主,不参与网络;避免 compose 并发创建第二个网络
    # 触发旧内核 Docker 的 bridge 配置竞态(导致 rustfs 网络无网关 IP)。
    network_mode: none
    volumes:
      - ${RUSTFS_DATA_0_DIR:-./volumes/rustfs0}:/data/rustfs0
      - ${RUSTFS_LOGS_DIR:-./volumes/logs}:/app/logs
    command: >
      sh -c "
        chown -R 10001:10001 /data/rustfs0 /app/logs &&
        echo 'Bind mount permissions fixed to 10001:10001' &&
        exit 0
      "
    restart: "no"
```

应用修改:

```bash
docker compose config >/dev/null   # 校验语法
docker compose down
docker compose up -d
```

## 验证结果

完整执行一次 `docker compose down && docker compose up -d` 后:

- 只创建了一个网络 `rustfs_rustfs-network`,`rustfs_default` 不再产生。
- 网桥正常:

```text
br-827b23ee7d49: <BROADCAST,MULTICAST,UP,LOWER_UP> state UP
    inet 172.29.0.1/16 scope global br-827b23ee7d49
```

- 容器健康:

```text
rustfs-server Up (healthy) 0.0.0.0:49000->9000/tcp, 0.0.0.0:49001->9001/tcp
```

- 访问验证:

```text
console49001   = 200
s3_49000       = 200
lan_console    = 200
```

Console 地址:`http://<宿主机IP>:49001/rustfs/console`

## 备注

- 该问题与 RustFS 本身无关,属于 Docker 在旧内核上的网桥创建竞态。
- 其他 compose 变体如果保留了 `volume-permission-helper`,同样已加上 `network_mode: none`(本次已全部修复)。
- 应急手动修复(不改 compose、仅临时恢复):用特权容器给问题网桥补网关 IP 并拉起。

```bash
# 先查出 rustfs 网络对应的网桥名
id=$(docker network inspect -f '{{.Id}}' rustfs_rustfs-network)
br="br-${id:0:12}"

docker run --rm --privileged --net=host alpine sh -c \
  "ip link set $br up; ip addr add 172.30.0.1/16 dev $br"
```

注意:手动修复在删除/重建网络或重启后会失效,推荐使用 `network_mode: none` 的正式修复。

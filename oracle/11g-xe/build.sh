#!/usr/bin/env bash
# Oracle 11g XE 优化镜像构建脚本(amd64 / arm64)
#
# 用法:
#   1. 本机构建(自动匹配当前架构,构建后导入本地 docker):
#        ./build.sh
#        ./build.sh myrepo/oracle-xe-11g:1.0.0
#
#   2. 双架构构建并推送到镜像仓库(需要 buildx 与仓库登录):
#        PUSH=1 ./build.sh myrepo/oracle-xe-11g:1.0.0
#
# 说明:
#   - Oracle 11g 官方只提供 x86-64 二进制。arm64 镜像基于 amd64 base 构建、
#     在 qemu/Rosetta 模拟层下运行,启动比 amd64 慢,仅供开发/测试。
#   - 在 arm64 宿主机(如 Apple Silicon)上直接 docker build 也会通过
#     Docker Desktop 的 Rosetta/qemu 模拟完成,产物可用但性能打折。
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-oracle-xe-11g}"
IMAGE="${1:-$IMAGE_NAME:1.0.0}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"

# 当前宿主机架构 → docker platform 写法
ARCH="$(uname -m | sed 's/^x86_64$/amd64/; s/^aarch64$/arm64/')"

if [ "${PUSH:-0}" = "1" ]; then
  echo ">>> 多架构构建并推送: $IMAGE ($PLATFORMS)"
  docker buildx build --platform "$PLATFORMS" -t "$IMAGE" --push .
else
  echo ">>> 本机($ARCH)构建: $IMAGE"
  docker buildx build --platform "linux/$ARCH" -t "$IMAGE" --load .
fi

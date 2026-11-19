#!/usr/bin/env bash
#
# Copyright 2024 RustFS Team
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# 生成 docker-compose.fixed-latest.yml:
#   1. 读取同目录下的 repo.json,得到上游仓库地址与镜像名;
#   2. 查询上游最新 release 的 tag;
#   3. 复制 docker-compose.yml,仅把镜像行固定为「镜像名:最新 tag」,其余内容保持不变。
#
# 用法: ./generate_fixed_latest.sh
# 可选环境变量: GITHUB_TOKEN(访问 GitHub API 时提高速率上限)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_JSON="${SCRIPT_DIR}/repo.json"

[ -f "${REPO_JSON}" ] || { echo "错误: 未找到 ${REPO_JSON}" >&2; exit 1; }

# 读取 JSON 字段(优先 jq,其次 python3)
json_get() {
  local path="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -er "${path}" "${REPO_JSON}"
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "${REPO_JSON}" "${path}" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
cur = data
for key in sys.argv[2].lstrip(".").split("."):
    cur = cur[key]
print(cur)
PY
  else
    echo "错误: 需要 jq 或 python3 来解析 repo.json" >&2
    exit 1
  fi
}

REPOSITORY="$(json_get '.repository')"
IMAGE="$(json_get '.image')"
COMPOSE_FILE="$(json_get '.compose_file')"
OUTPUT_FILE="$(json_get '.output_file')"

SOURCE_COMPOSE="${SCRIPT_DIR}/${COMPOSE_FILE}"
TARGET_COMPOSE="${SCRIPT_DIR}/${OUTPUT_FILE}"

[ -f "${SOURCE_COMPOSE}" ] || { echo "错误: 未找到 ${SOURCE_COMPOSE}" >&2; exit 1; }

# 从仓库地址解析 owner/repo,例如 https://github.com/rustfs/rustfs -> rustfs/rustfs
REPO_SLUG="${REPOSITORY%.git}"
REPO_SLUG="${REPO_SLUG%/}"
REPO_SLUG="${REPO_SLUG#*://}"
REPO_SLUG="${REPO_SLUG#*/}"
if [ "$(printf '%s' "${REPO_SLUG}" | awk -F/ '{print NF}')" != "2" ]; then
  echo "错误: repo.json 中的 repository 无法解析出 owner/repo: ${REPOSITORY}" >&2
  exit 1
fi

# 查询最新 release tag:优先用 /releases/latest 的 302 跳转(不受 API 限流影响),
# 失败时回退到 GitHub API。
fetch_latest_tag() {
  local slug="$1" tag="" effective=""

  effective="$(curl -fsSL -m 30 -o /dev/null -w '%{url_effective}' \
    "https://github.com/${slug}/releases/latest" 2>/dev/null || true)"
  case "${effective}" in
    */releases/tag/*) tag="${effective##*/releases/tag/}" ;;
  esac

  if [ -z "${tag}" ]; then
    local auth=()
    [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    tag="$(curl -fsSL -m 30 "${auth[@]}" \
      -H 'Accept: application/vnd.github+json' \
      "https://api.github.com/repos/${slug}/releases/latest" 2>/dev/null \
      | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 || true)"
  fi

  [ -n "${tag}" ] || return 1
  printf '%s\n' "${tag}"
}

TAG="$(fetch_latest_tag "${REPO_SLUG}")" || {
  echo "错误: 无法获取 ${REPO_SLUG} 的最新 release,请检查网络后重试" >&2
  exit 1
}

# Docker 镜像 tag 一般不带前导 v
IMAGE_TAG="${TAG#v}"

# 复制 compose 文件,仅替换镜像行
if ! awk -v image="${IMAGE}" -v tag="${IMAGE_TAG}" '
  !replaced && /^[[:space:]]*image:[[:space:]]*/ && index($0, image ":") > 0 {
    indent = $0
    sub(/[^[:space:]].*$/, "", indent)
    printf "%simage: %s:%s\n", indent, image, tag
    replaced = 1
    next
  }
  { print }
  END { if (!replaced) { printf("错误: 未在 compose 文件中找到镜像行 %s:<tag>\n", image) > "/dev/stderr"; exit 2 } }
' "${SOURCE_COMPOSE}" > "${TARGET_COMPOSE}"; then
  rm -f "${TARGET_COMPOSE}"
  exit 1
fi

echo "已生成 ${OUTPUT_FILE}"
echo "  上游仓库: ${REPOSITORY}"
echo "  最新版本: ${TAG}"
echo "  固定镜像: ${IMAGE}:${IMAGE_TAG}"

#!/usr/bin/env bash
# 将项目文件夹打包为 tgz 放到 pack/ 目录下，并在 pack/pack.json 中记录打包时间。
# 用法:
#   ./pack.sh            # 打包所有项目
#   ./pack.sh rustfs ... # 只打包指定的项目（可传任意多个）

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_DIR="$ROOT_DIR/pack"
PACK_JSON="$PACK_DIR/pack.json"

mkdir -p "$PACK_DIR"

# 初始化 pack.json
if [[ ! -f "$PACK_JSON" ]]; then
    echo '{}' > "$PACK_JSON"
fi

# 项目目录 = 根目录下排除脚本自身、pack 目录和隐藏目录/文件
is_project() {
    local name="$1"
    [[ "$name" == "pack" ]] && return 1
    [[ "$name" == pack.sh ]] && return 1
    [[ "$name" == .* ]] && return 1
    [[ -d "$ROOT_DIR/$name" ]] || return 1
    return 0
}

ALL_PROJECTS=()
for entry in "$ROOT_DIR"/*; do
    name="$(basename "$entry")"
    if is_project "$name"; then
        ALL_PROJECTS+=("$name")
    fi
done

# 确定要打包的项目列表
if [[ $# -gt 0 ]]; then
    TARGETS=()
    for arg in "$@"; do
        if ! is_project "$arg"; then
            echo "错误: '$arg' 不是有效的项目目录，跳过" >&2
            continue
        fi
        TARGETS+=("$arg")
    done
else
    TARGETS=("${ALL_PROJECTS[@]}")
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
    echo "没有需要打包的项目" >&2
    exit 1
fi

for name in "${TARGETS[@]}"; do
    src="$ROOT_DIR/$name"
    out="$PACK_DIR/$name.tgz"
    echo "打包: $name -> pack/$name.tgz"
    tar -czf "$out" -C "$ROOT_DIR" "$name"

    # 记录打包时间（epoch 秒）到 pack.json
    now="$(date +%s)"
    tmp="$PACK_JSON.tmp"
    jq --arg name "$name" --argjson time "$now" \
        '.[$name] = $time' "$PACK_JSON" > "$tmp" && mv "$tmp" "$PACK_JSON"

    echo "完成: pack/$name.tgz ($(date -d "@$now" '+%Y-%m-%d %H:%M:%S'))"
done

echo "全部打包完成，时间记录见 pack/pack.json"

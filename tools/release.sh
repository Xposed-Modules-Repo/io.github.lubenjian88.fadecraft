#!/usr/bin/env bash
#
# 一键发版到 Xposed-Modules-Repo / modules.lsposed.org
#
#   bash tools/release.sh 1.1.9 24 [更新说明.md]
#
# 必须在**模块仓库的根目录**执行（就是被 bot 建出来的、仓库名等于包名的那个仓库）。
# 脚本做三件事：
#   1. 从 FadeCraft 的 dist 目录取 APK，复制成 <包名>-<版本>.apk
#   2. 建一个 tag 为 "<版本码>-<版本名>" 的 Release（官方要求的格式）
#   3. 把 APK 传上去
#
# 为什么 tag 一定要这个格式：仓库页和你模块的更新提示都靠它识别版本，
# 格式不对 bot 会自己改，但改完要等 5~60 分钟才同步到网站。
#
# APK 默认从 ../FadeCraft/dist 取（本机的目录结构）。如果仓库是单独 clone 的，
# 用环境变量指过去：FC_DIST=/path/to/FadeCraft/dist bash tools/release.sh 1.1.9 24

set -euo pipefail

VER="${1:-}"
CODE="${2:-}"
NOTES_FILE="${3:-}"

PKG="io.github.lubenjian88.fadecraft"
DIST="${FC_DIST:-../FadeCraft/dist}"

if [ -z "$VER" ] || [ -z "$CODE" ]; then
  echo "用法：bash tools/release.sh <版本名> <版本码> [更新说明文件]"
  echo "例：  bash tools/release.sh 1.1.9 24"
  exit 1
fi

TAG="${CODE}-${VER}"
APK="$DIST/FadeCraft-${VER}.apk"

echo "==> 包名 $PKG / 版本 $VER ($CODE) / tag $TAG"

[ -f "$APK" ] || { echo "！找不到 APK：$APK"; exit 1; }

if ! command -v gh >/dev/null 2>&1; then
  echo "！需要 GitHub CLI：https://cli.github.com"
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "！当前目录不是 git 仓库，请在模块仓库根目录执行"
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "！还没登录 GitHub，先执行：gh auth login"
  exit 1
fi

# 资产名用「包名-版本.apk」，安装器下载下来一眼能认
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ASSET="$TMP/${PKG}-${VER}.apk"
cp "$APK" "$ASSET"

NOTES=""
if [ -n "$NOTES_FILE" ] && [ -f "$NOTES_FILE" ]; then
  NOTES="$(cat "$NOTES_FILE")"
fi
[ -n "$NOTES" ] || NOTES="$VER"

# tag 已存在就先删掉（同一个版本重发的情况）
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "==> tag $TAG 已存在，先删除旧 Release"
  gh release delete "$TAG" --yes
  git push --delete origin "$TAG" 2>/dev/null || true
fi

echo "==> 创建 Release"
gh release create "$TAG" "$ASSET" \
  --title "$VER" \
  --notes "$NOTES"

echo "==> 完成"
echo "    https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases/tag/$TAG"
echo "    5~60 分钟后同步到 https://modules.lsposed.org/module/$PKG"

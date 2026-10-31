#!/usr/bin/env bash
#
# 一键把模块仓库内容推到 Xposed-Modules-Repo 并发布 Release。
#
#   TOKEN=ghp_xxx  bash tools/publish.sh
#
# 前置条件：
#   1. 已经在 https://modules.lsposed.org/submission/ 提交过包名
#      （bot 会建好 github.com/Xposed-Modules-Repo/io.github.lubenjian88.fadecraft 并给你推送权限）
#   2. TOKEN 对上面那个仓库有 push + 创建 Release 的权限：
#      - 经典 PAT（勾 repo 范围）会自动覆盖；
#      - 精细 PAT（github_pat_ 开头）需要在 GitHub 里把这个仓库加到 token 的「Repository access」。
#
# 脚本做：push SUMMARY + README（+ SUBMIT.md / tools）到 main，
# 然后建 tag = <版本码>-<版本名> 的 Release 并上传 APK。
# 不依赖 gh，纯 git + curl。

set -euo pipefail

TOKEN="${TOKEN:-${GH_TOKEN:-}}"
if [ -z "$TOKEN" ]; then
  echo "！用法：TOKEN=你的GitHubToken bash tools/publish.sh"
  exit 1
fi

REPO="Xposed-Modules-Repo/io.github.lubenjian88.fadecraft"
PKG="io.github.lubenjian88.fadecraft"
VER="${VER:-1.2.4}"
CODE="${CODE:-29}"
APK="${FC_DIST:-../FadeCraft/dist}/FadeCraft-${VER}.apk"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[ -f "$APK" ] || { echo "！找不到 APK：$APK"; exit 1; }

echo "==> 添加远端并推到 $REPO"
git remote remove origin 2>/dev/null || true
git remote add origin "https://x-access-token:${TOKEN}@github.com/${REPO}.git"
git branch -M main
git push -u origin main --force-with-lease

TAG="${CODE}-${VER}"
API="https://api.github.com/repos/${REPO}"

echo "==> 创建 Release（tag $TAG）"
# 旧 tag 先清掉（重发场景）
curl -s -X DELETE -H "Authorization: Bearer $TOKEN" "$API/releases/tags/$TAG" >/dev/null 2>&1 || true
REL=$(curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
  -H "Content-Type: application/json" "$API/releases" \
  -d "{\"tag_name\":\"$TAG\",\"name\":\"$VER\",\"body\":\"$VER\",\"draft\":false,\"prerelease\":false}")

UPLOAD_URL=$(printf '%s' "$REL" | python -c "import sys,json
try:
    d=json.load(sys.stdin); print(d.get('upload_url','').replace('{?name,label}',''))
except: print('')" 2>/dev/null)

if [ -z "$UPLOAD_URL" ]; then
  echo "！创建 Release 失败，响应："; printf '%s' "$REL" | head -c 500; echo
  exit 1
fi

echo "==> 上传资产 APK"
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/vnd.android.package-archive" \
  --data-binary @"$APK" "${UPLOAD_URL}?name=${PKG}-${VER}.apk" >/dev/null

echo "完成 ✅"
echo "  仓库：https://github.com/${REPO}"
echo "  发布：https://github.com/${REPO}/releases/tag/${TAG}"
echo "  5~60 分钟后同步到 https://modules.lsposed.org/module/${PKG}"

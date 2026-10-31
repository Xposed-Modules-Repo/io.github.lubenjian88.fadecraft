# 上架 LSPosed 官方模块仓库（modules.lsposed.org）

规则来自 <https://github.com/Xposed-Modules-Repo/submission>，提交入口
<https://modules.lsposed.org/submission/>。

## 0. 包名已定：`io.github.lubenjian88.fadecraft`

官方要求反向域名必须是自己的域名，否则得用 `io.github.{username}` 前缀。
GitHub 账号 `lubenjian88` 名下没有 `fadecraft.com`，因此按第二种办，从
`com.fadecraft` 迁到 **`io.github.lubenjian88.fadecraft`**（1.1.9 起）。

迁移时**只动了 applicationId 和 10 处包名字符串**，Java 包名仍是 `com.fadecraft`，
所以 `xposed_init` 里的类路径、`R` 类、所有 import 都没变。改的位置：

| 文件 | 内容 |
|---|---|
| `app/build.gradle` | `applicationId` |
| `AndroidManifest.xml` | provider 的 `android:authorities` |
| `CfgProvider.java` | `AUTHORITY = "…fadecraft.cfg"` |
| `ConfigIO.java` | `PKG_APP` |
| `SettingsHook.java` | 4 处（取资源、取图标、跳转 Activity） |
| `MainActivity.java` | `ICON_ALIAS`（activity-alias 全名） |
| `tools/build-manual.sh` | 注入 manifest 的 `package=` |

> **手工构建必须加 `--custom-package com.fadecraft`**（已经加进脚本）。
> aapt2 默认按 manifest 的 package 生成 R.java，改包名后会生成到
> `io.github.lubenjian88.fadecraft.R`，而源码写的是 `com.fadecraft.R`，
> 直接 58 个「找不到符号」。这就是 AGP 里 namespace 与 applicationId 的区别，
> 手工构建要自己拆开。

## 1. 提交

1. 打开 <https://modules.lsposed.org/submission/>
2. 选 **Submit a new package**
3. Package name 填 `io.github.lubenjian88.fadecraft`
4. Description 填：

   > 熄屏动画模块，接管电源键熄屏的最后一帧，播放碎片化解体动画后再交给系统睡眠。
   > 仅注入 SystemUI，无网络权限，无后台常驻服务。

5. 点 **Submit on GitHub**，会生成一个预填 issue
6. 确认标题是 `[submission] io.github.lubenjian88.fadecraft`，提交

> 因为包名用了 `io.github.lubenjian88` 前缀，**提交前先把 GitHub 的
> 组织成员身份设为 public**（Settings → Public profile → Organizations），
> 否则验证过不去。

## 2. 等 bot 建仓库

bot 会：
- 在 `Xposed-Modules-Repo` 组织下建一个名为 `io.github.lubenjian88.fadecraft` 的仓库
- 把你加为 maintainer（GitHub 有邀请，**必须点接受**）

## 3. 往里推文件

只放两个文件，**不要传源码**：

```
SUMMARY      ← 首页显示的一行摘要（本目录已备好）
README.md    ← 模块详情页（本目录已备好）
```

```bash
git clone https://github.com/Xposed-Modules-Repo/io.github.lubenjian88.fadecraft.git
cd io.github.lubenjian88.fadecraft
cp ../LSPosedRepo/SUMMARY ../LSPosedRepo/README.md .
git add . && git commit -m "docs: 初始化" && git push
```

## 4. 仓库设置（只能在网页改）

- **Description** → 填模块名 **`熄屏幻术`**
  （官网卡片上显示的就是这一行；官方明确说 API 改不了，只能浏览器里改）
- **Homepage** → 反馈链接，可以先填本仓库 Issues

> LSPosed 管理器里显示的那行「作者：7513   抖音：lubenjian88」来自 APK 清单的
> `xposeddescription`，和这里的 Description 是两回事，两边都要对。

## 5. 发第一个 Release

官方要求 tag 必须是 **`版本码-版本名`**，当前版本对应 **`24-1.1.9`**。

```bash
# 在仓库根目录执行
bash tools/release.sh 1.1.9 24
```

脚本会取 `../FadeCraft/dist/FadeCraft-1.1.9.apk`，复制成
`io.github.lubenjian88.fadecraft-1.1.9.apk`，建一个标题 `1.1.9`、tag `24-1.1.9`
的 Release 并上传。

手工做也行，只要满足：标题=版本名、正文=更新日志、至少一个 `.apk` 资产、
tag=`24-1.1.9`。

## 6. 等同步

仓库内容完整后（Description + 至少一个带 apk 的 Release + SUMMARY/README），
`modules` 仓库会触发构建，**5~60 分钟**后出现在
<https://modules.lsposed.org/module/io.github.lubenjian88.fadecraft>。

## 踩过的坑

- **只换 APK 不会更新 tag**。改 Release 的资产不会触发 webhook，bot 不知道你改过，
  tag 就不会被纠正。要改就整条 Release 重发（脚本已处理：先删旧的再建）。
- 仓库不完整就不显示。缺 Description、缺 Release、Release 里没有 apk，任一都算不完整。
- 别把 `tools/`、`SUBMIT.md` 推上去 —— 官方只要 `SUMMARY` + `README.md` + 元数据。
- 迁包名后老用户必须**卸载重装**：签名一样也没法覆盖，配置、作用域、桌面图标都要重来。

## 后续发版 checklist

1. 改 `app/build.gradle` 的 `versionCode` / `versionName`
2. `bash tools/build-manual.sh`（带 `VERSION_NAME` / `VERSION_CODE` 环境变量）
3. 装机验证（至少播一次特效）
4. `bash tools/release.sh <版本名> <版本码> notes.md`
5. 功能有变就同步更新仓库里的 `SUMMARY` / `README.md`

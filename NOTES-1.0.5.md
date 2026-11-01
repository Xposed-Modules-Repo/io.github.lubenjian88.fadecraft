1.0.5 —— 抓帧重写，Xiaomi 17 / HyperOS 4 也能正常播了

## 修好了什么

**1. 「动画播了，但画面是暗色渐变，看不见屏幕内容」**

Xiaomi 17 / HyperOS 4.0.0.43（Android 17）上，ROM 把 system 进程的镜像抓屏权限
（`ADD_MIRROR_DISPLAY` / `CAPTURE_VIDEO_OUTPUT` / `CAPTURE_SECURE_VIDEO_OUTPUT`）
收回了，建镜像虚拟屏一律抛：

```
SecurityException: Requires ADD_MIRROR_DISPLAY, CAPTURE_VIDEO_OUTPUT or
CAPTURE_SECURE_VIDEO_OUTPUT permission ... to create a screen sharing virtual display
```

1.0.4 及更早的五条抓帧路径（mirror / captureDisplay / ScreenCapture / SC(Rect) / SC(legacy)）
在这台机器上全部走不通，只能退回兜底暗色画面。

1.0.5 换了一条根本不需要虚拟屏的路：`IWindowManager.captureDisplay(displayId, …)`
—— 它收的是 displayId 而不是 display token，token 由 system_server 内部自己填。
实测抓帧从 **~85ms 降到 ~30ms**，且不碰上面那几个权限。

**2. 「动画播完会闪一下壁纸才黑屏」**

旧逻辑在动画播完后按固定延时撤黑帧。但系统从「开始灭屏」到「面板真正断电」要
400~600ms，中间面板还在做亮度淡出，黑帧一撤就把锁屏壁纸露出来约 100ms。

1.0.5 改成轮询 `Display.getState()`，一直盖到状态真的变成 `OFF`；
万一这次压根没熄屏（睡眠被别的应用挡住、或用户中途又按亮了屏），
会走 150ms 淡出，而不是硬切。

**3. 其他**

- 抓屏权限兜底：即使 ROM 继续收紧，注入在 system_server 里的权限放行钩子也会
  只对 system uid（SystemUI / system_server）放行那几个抓屏权限，第三方应用照旧被拦。
- 日志新增 `display state <n> (+<ms>ms)` 状态轨迹与抓帧亮度 `mean=`，
  以后反馈「黑屏 / 没画面」时，一行就能分清是没抓到还是抓到了黑帧。

## 注意

- **更新后请整机重启手机**。拦截电源键的核心逻辑在 system_server 里，应用内的
  「重启作用域」只重启 SystemUI + 系统设置，碰不到它。
- 适用范围：Android 10（API 29）及以上；本次在 Android 17 / HyperOS 4
  （Xiaomi 13 fuxi、Xiaomi 17 popsicle）上验证通过。

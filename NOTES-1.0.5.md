1.0.5 —— 抓帧重写 + 熄屏收尾重做：不闪壁纸，解锁震动也回来了

这一版集中解决「熄屏最后一秒」这一段的四个问题：看不见画面、播完闪一下壁纸、
指纹/人脸解锁没震动、以及关掉震动后反而震两次。四件事的根都在同一处 ——
熄屏是个跨进程、跨几百毫秒的过程，而旧实现把其中几段时间当成了常数。

## 修好了什么

**1. 「动画播了，但画面是暗色渐变，看不见屏幕内容」**

Xiaomi 17 / HyperOS 4.0.0.43（Android 17）上，ROM 把 system 进程的镜像抓屏权限
（`ADD_MIRROR_DISPLAY` / `CAPTURE_VIDEO_OUTPUT` / `CAPTURE_SECURE_VIDEO_OUTPUT`）
收回了，建镜像虚拟屏一律抛：

```
SecurityException: Requires ADD_MIRROR_DISPLAY, CAPTURE_VIDEO_OUTPUT or
CAPTURE_SECURE_VIDEO_OUTPUT permission ... to create a screen sharing virtual display
```

旧版本的五条抓帧路径（mirror / captureDisplay / ScreenCapture / SC(Rect) / SC(legacy)）
在这台机器上全部走不通，只能退回兜底暗色画面。

现在换了一条根本不需要虚拟屏的路：`IWindowManager.captureDisplay(displayId, …)`
—— 它收的是 displayId 而不是 display token，token 由 system_server 内部自己填。
实测抓帧从 **~85ms 降到 ~30ms**，且不碰上面那几个权限。

**2. 「动画播完会闪一下壁纸才黑屏」**

旧逻辑在动画播完后按固定延时撤黑帧。但系统从「开始灭屏」到「面板真正断电」要
400~600ms，中间面板还在做亮度淡出，黑帧一撤就把锁屏壁纸露出来约 100ms。

现在改成轮询 `Display.getState()`，一直盖到状态真的变成 `OFF`；
万一这次压根没熄屏（睡眠被别的应用挡住、或用户中途又按亮了屏），
走 150ms 淡出，而不是硬切。

**2b. 同一条路上更慢的那种机型**

Redmi garnet（Android 16 / HyperOS 3）上还残留过一次闪烁，日志给出了完整时间线：

```
17:47:12.894  requestPlay -> 1452ms
17:47:16.848  sleep cap fired (animation report missing)   ← 本该在 +2352ms
```

慢了整整 1.6 秒。原因是「补睡」这个定时器挂在 **system_server 的主线程**上，
而熄屏那一瞬主线程正被系统自己的任务（锁屏、转场、亮度与显示状态广播）塞满，
`postDelayed` 整体迟到。于是黑帧的宽限期先到期 → 淡出 → 壁纸露 450ms → 才灭屏。

两处改动：宽限期 3.5 秒 → **9 秒**（它只是「万一永远不灭屏」的保险丝，不是工作值，
这段时间盖的是纯黑帧，多盖几百毫秒没有观感代价）；补睡的定时器在模块自己的
`fadecraft-power` 线程上**再挂一份**（晚 400ms），谁先到算谁。熄屏延迟从 3.95 秒压回 ~2.4 秒。

**3. 「指纹 / 人脸识别解锁的震动没了」**

模块会吞掉系统那一下「迟到的锁屏震动」——它本该和按键同时，却被动画推迟了整整一个时长，
不吞就会变成「先震一下，过一秒又震一下」。

问题是吞的范围：旧实现是「从开播起，2.7 秒内第一次来自 SystemUI 的震动一律吞掉」，
system_server 侧还另有一个 4 秒的窗口。熄屏后一秒内按指纹解锁，
**被吞的其实是解锁那一震** —— 时间上完全落在窗口里。

现在两个窗口都改成**按事件锚定**：

| | 旧 | 现在 |
|---|---|---|
| SystemUI 侧 | 开播起 `动画时长 + 1500ms`（≈2.7s） | 动画播完 / keyguard 上锁那一刻起 **900ms** |
| system_server 侧 | 按键起固定 **4000ms** | `[动画结束 − 250ms, 动画结束 + 500ms]` |
| 命中后 | 关闭窗口（只吞一次） | 保留到自然过期（一次上锁可能连发两三个出口） |

真机实测（Xiaomi 13 fuxi）时间戳对得上：

```
18:15:54.347  arm haptic mute 900ms
18:15:54.352  keyguard playSound id=1 suppress=true
18:15:54.356  mute late lock haptic (vibrate) id=1000
18:15:54.828  display state 1 (+482ms) → 撤黑帧
18:15:58.136  keyguard playSound id=2 suppress=false    ← 解锁，没有被吞
```

窗口在 54.356 之后就收口了，解锁发生在 58 秒，相差 3.6 秒，不可能误伤。

**3b. 这个窗口和「震动反馈」开关无关**

它消除的是**动画把系统震动往后推**这个副作用，不是「模块要不要替你震一下」。
两者必须分开，否则会互相打架：

| 震动开关 | 模块补的那一下 | 系统迟到的那一下 | 结果 |
|---|---|---|---|
| 开 | 震（按键瞬间） | 吞掉 | 震一次 |
| 关 | 不震 | 吞掉 | 系统原本那一次 |

早期实现把窗口跟开关绑在一起，于是关掉震动的人反而被震两次：
系统按键时那一次照常，动画结束后迟到那一次没人吞。这个窗口现在无条件布防。

**4. 其他**

- 抓屏权限兜底：即使 ROM 继续收紧，注入在 system_server 里的权限放行钩子也会
  只对 system uid（SystemUI / system_server）放行那几个抓屏权限，第三方应用照旧被拦。
- 日志新增 `display state <n> (+<ms>ms)` 状态轨迹与抓帧亮度 `mean=`，
  以后反馈「黑屏 / 没画面」时，一行就能分清是没抓到还是抓到了黑帧。
- 被吞的震动日志带上 `id=`，下次再报「震动丢了」，看 id 就能分清被吞的是锁屏那一下
  还是解锁那一下。
- SystemUI 侧的现场记录改成双通道回传（指名发给 `android` + 隐式广播），
  某些 ROM 会把指名广播直接丢掉，那样日志里连一行 SystemUI 记录都看不到。

## 注意

- **更新后请整机重启手机**。拦截电源键的核心逻辑在 system_server 里，应用内的
  「重启作用域」只重启 SystemUI + 系统设置，碰不到它。
- 适用范围：Android 10（API 29）及以上。本次在 Android 17 / HyperOS 4.0.5.0
  （Xiaomi 13 fuxi、Xiaomi 17 popsicle）上验证；Android 16 / HyperOS 3
  （Redmi garnet）的复现日志作为第 2b、3 条改动的依据。
- 已知遗留：个别 ROM 上 `ACTION_PLAYING` / `ACTION_DONE` 到不了 system_server，
  这时屏幕会亮着多等约 1.2 秒（黑帧盖着，看不见）。指向该问题的日志特征是
  `sleep cap fired (animation report missing)`，本版已双发兜底，若仍出现请附日志反馈。

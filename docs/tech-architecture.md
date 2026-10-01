# 雪皇的后厨 · 千星奇域移植 · 技术架构（living doc）

> **这份是交付后的运维手册**：谁负责什么、数据怎么流、改动要碰哪里。
> 每次**结构性改动**都必须更新它 —— 过时的条目比没有更糟。
> 最近一次更新：2026-09-27（还原度重做 r1：键位/手法/小票寻路/名额口径）
> **2026-10-01 晚：加入"写入链路诊断"构建**（`lua/src/diag.lua` + 写入点观测 + `forceWrite` 开关）——
> 见第八节。这是**临时观测代码**，确诊后要连同写入点改动一起回退。

---

## 一、这套东西是什么

- **原作**：`雪皇的后厨.html`（单文件 117 KB、零依赖、浏览器直接跑）。**它是规格书**。
- **移植**：`lua/src/*.lua` → 合成为单文件 `dist/xuehuang.lua` → 挂到千星的**客户端控件容器**上运行。
- **不做的**：3D 关卡图、联机（信号延迟 ≥100ms 是硬边界）。只做单人 2D + 客户端 Lua。

一句话数据流：

```
玩家输入(键/鼠标) → input.lua → xuehuang.lua(入口/状态机) → game.lua(G.act) → kitchen/order/day → state
                                                                                   ↓
                                                          view.lua(控件池) ← G.s（唯一状态源）
```

**唯一状态源**：`state.lua` 的 `G.s`。任何模块都不许另开变量存游戏数据。

---

## 二、模块职责（改东西先看这张表）

| 文件 | 职责 | 不许做的事 |
|---|---|---|
| `config.lua` | **所有数值的唯一来源**：模式/耐心/到店/收益/房租/手法/上限/UI 常量 | 不许有行为逻辑 |
| `recipes.lua` | 6 个产品：步骤（`st` 工位 + `t` 文案 + `kind` 手法 + `taps` 次数 + `noSlot`/`serveNow`/`heavy`）+ 工序量 `load` | 不许写"怎么判定完成" |
| `state.lua` | 局状态容器 `S.new`、派生查询 `nextStep` / `cupWip` / `wipCount` / `wipGateCount` / `dayFrac` | 不许被 UI 直接改动 |
| `order.lua` | 点单：随机口味/杯数、耐心（在制/排队/做完三档掉率）、结单结算、离店 | 不许碰控件 |
| `kitchen.lua` | ★核心：名额池 `refreshSlots`、出票 `makeTicketsFor`、挂票 `routeSlip`、**手动流转 `forwardSlip`**、手法推进 `pressStep`/`tickHolds`、收口 `doStep`、交付 `deliverCup`/`serveCup`、自动流转 `autoForward`、翻车 `doWrong`、僵尸票清理 `sweepZombieSlips` | 不许碰控件、不许碰输入 |
| `day.lua` | 时间推进 `tick`、到店、打烊/清场、每日结算（幂等闸 `settledDay`）、评级 | 同上 |
| `game.lua` | 主循环 `newGame`/`tick`、**玩家动作入口 `G.act`**（含 `opt.route` 自动送票）、事件 `on/emit`、BGM 无 | 不许写具体规则（规则在 kitchen/day） |
| `skin.lua` | 视觉层**唯一数值源**：尺寸/字号/间距/配色/素材号/版式坐标 | 不许出现业务数据 |
| `props.lua` | **实物视觉件**（2026-09-27 新增）：杯子 `P.cup`（侧壁 8.75° 陡锥 + **平液面** + 进度 `setFill`）、炮筒 `P.cone`（筒口→握把→锥体→尖）、火 `P.fire`（**DOOM 火焰算法**，16×27 = 432 格，`step`/`draw`）+ **规格已圈定 2026-10-01**（用户网页圈定）：火炬 筒口 120×18 / 握把 84×34 / 锥体 104×214（尖 6）；火 16×27 格、**每格 = 筒口宽/16 × 0.75**（不写死，见 `P.fireCellW`）；**火底边 = 筒口顶边**（入口 `P.torchWithFire`）；+ 规格 `P.spec` + 25 级调色板 `P.PAL` + 饮料真色 `P.drink` + 自带 LCG 伪随机 | **只画形状，不碰玩法**；规格数值必须与 `preview/design/*.html` 定稿一致；**不许用 `math.random`**（沙箱拦） |
| `view.lua` | 控件池 + 状态同步 `V.sync`：4 工位卡 + 打包台 + HUD + 等候区面板 + 5 订单卡 + **6 张小票卡** + 营业数据 + 手册/快捷键 + 菜单/结算页。**工位状态机 `V.stationState` + 每秒状态行 `V.stateLine`** | 不许自己造数（全部来自 `s`）、不许直接改状态、**不许各处自写"有没有活"的判据** |
| `input.lua` | 按键绑定（`IN.BIND` 唯一真相）+ 光标点击 + 命中测试 `IN.hit` + 事件派发 `IN.pump` | 不许决定"动作做什么"（那是入口/玩法的事） |
| `host.lua` | 平台能力：挂载点、模板扫描、素材号、建控件 `spawn`（`spawn(cfg,kind,name,parent)`，第 4 个 parent **可选**，用于嵌套视觉件）、画布、隐藏空控件、常驻光标 | 不许含玩法或版式 |
| `xuehuang.lua` | ★入口：生命周期、场景状态机（menu/play）、输入路由（键→界面层/玩法层）、提示文案 | 不许含玩法规则 |
| `diag.lua` | **★ 临时：写入链路诊断**（2026-10-01）。`D.try(tag,控件,值,fn)` 检查每次控件写入的 pcall 返回值、失败打一行 ASCII `[WERR]`；缓存命中但该控件上次写失败 ⇒ 打 `[WERR-CACHE]`（缓存投毒的直接证据）；每 30 帧一行 `[WERR-SUM]`。**只观测，不改行为** | 不许带玩法逻辑；确诊后删除 |

---

## 三、关键数据流（三条链路）

### 1. 输入链路（玩家 → 逻辑）

```
AddKeyEventListener(Enum.KeyEventType.KeyboardCraftspersonKeyN Down/Up)   ← 监听挂在"光标检测区域 + 容器根节点"两处
   → input.lua 的 dispatch(act, kind)          ↑ act 是语义名：shake/fire/chem/brew/pack/mode1..3/confirm/click
   → IN.pump 每帧把 handlers.act 发布到 _G.__IN_ACT（回调直呼，不走帧队列）
   → xuehuang.lua OnUpdate 的 act 回调：
        ① uiAct('click') / uiAct(act)      ← 界面层优先：菜单选模式、开门、结算继续
        ② mode1/2/3                         ← 营业中 = 自动流转 / 自动出票 / 暂停
        ③ 工位键 → G.act(act, kind, nil, { route = true })   ← ★带自动送票
        ④ click → 先命中工位卡（=按那个工位键）→ 再命中小票卡（=forwardSlip）
```

⚠️ **`opt.route = true` 是"按下去一定有回应"的那一环**：票不在这个工位时，先把"下一步就是本工位"的票
送过来（等价原版"点小票立刻送过去"），再动手。它**不抢别的工位的活**（该去 chem 的票，按 shake 依然拒绝）。

### 2. 玩法链路（一局怎么跑）

```
G.tick(dt) → day.lua D.tick：
    到店 O.spawn → 耐心按档位下降 → 到点离店 O.leave
    K.refreshSlots（名额池：发资格 slotReady / 补票 / 硬上界）
    K.tickHolds（按住类每帧累积进度）→ K.sweepZombieSlips → K.autoForward（闲 5 秒自动流转）
打烊：dayLeft≤0 → phase=closing（耐心冻结）→ 宽限期到 → 结算（幂等）→ 下一天
```

### 3. 表现链路（状态 → 画面）

```
每帧 V.sync(v, G.s)                       ← 只读 s，幂等
   工位卡：问 V.stationState(s, 工位) → 三态之一：
        'work'    有活可做 → 原色 + 步骤文案 + 进度条
        'waiting' 有活但没名额 → "有活 · 等名额腾出来"（★ 这一态以前没有，是显示 bug 的根源）
        'nw'      真没活 → 压暗 + "本工位无活（按 X 无效）"
   小票行：每张票三行 = 谁 / 下一步做什么（按住类标"按住 0.9 秒"、连按类标"连按 N 下"）
                        / 点我送去哪。★ 这里的判据**也必须问 V.stationState**
   打包台：有杯等出餐 → "可交付 N 杯 … ← 按 空格 出餐"
   玩区显隐每帧按 scene 对齐（单一数据源，不做"切换时调一次"）
   每秒一行 [STATE] ASCII（V.stateLine）：把"逻辑状态"与"画面"钉在同一行上，便于真机对照
```

⚠️ **显示层的铁律（用血换的）**：**同一个问题只能有一个判据函数**。
`V.stationState` 就是"这个工位能不能干活"的唯一答案；工位卡、小票卡、HUD 提示都必须问它。
历史上因为两处各写一套（工位卡用 `nextStep().st`、小票卡用 `sl.st`），
真机上出现"小票说按 P、工位卡说按 P 无效"的自相矛盾显示，玩家只能判定"按键无效"。

---

## 四、挂载点与平台契约（踩过的坑，别改回去）

| 事项 | 结论 |
|---|---|
| 挂载点 | **客户端控件容器**（脚本挂在它上面）；容器必须 active + visible，否则**不报错但脚本不跑** |
| 建控件时机 | `InstantiateClientUIControl` 在 `OnInit` 返回 nil → 必须在 `OnStart` 及之后；`OnUpdate` 里要有兜底 |
| Update | 必须 `script:EnableUpdate(true)`，否则永远收不到 `OnUpdate` |
| 调用风格 | `game` 全局函数用**点号**（`game.GetUICanvasSize()`），冒号会多传隐式实参 |
| 控件模板索引 | 大数字（`1073741xxx`），**不是** 1/2/3/4；`host.lua` 两个空间都扫 |
| 只读属性 | `imageSource` / `imageId` 只读 → 设图只能用 `SetImage(source, id)`；`imageType` 可写 |
| 画布 | 真机 1815×900（≈2.02:1）；2D 基线手机 1280×720；原点左下、y 向上 |
| 光标 | 容器 `showCursor=true`，否则玩家要按住 Alt 才看得见；点击要有"光标检测区域"控件且**必须有尺寸** |
| 中文 | 合成单文件时：注释里的非 ASCII 换空格、**字符串字面量里的转成 Lua 十进制转义**（绝不能一起换掉） |
| 脚本入库 | 脚本是**保存进关卡存档（.gil）**的；改了必须重新导入 + 保存关卡，否则跑的是旧版 |
| 运行期 | **只改属性，不新建/销毁控件** → 一律"控件池" |

---

## 五、名额口径（2026-09-27 定稿，改动前先读这段）

两个口径，**别混**：

| 口径 | 函数 | 语义 | 上界 |
|---|---|---|---|
| 文档口径："后厨同时最多 3 个未完成任务" | `S.wipCount`（= `S.cupWip` 求和） | 开工了**且当前步不是 `noSlot`** 的杯 | ≤ `maxWip`（3） |
| 闸门口径："同时开了多少杯" | `S.wipGateCount` | **只要 `startedAt ~= nil` 就算**（不分 noSlot） | ≤ `2 × maxWip`（6） |

- `noSlot`（例：速溶咖啡前三步）是**原版设计**：轻活不抢重活的名额。
- 但它**不能当"绕过名额闸门"的通行证** —— 我踩过：`beginWork` 里
  `if not freeStep and wipCount >= CAP then return false end` 让连按兑茶键能开出**无限杯**，
  端到端测试实测峰值 7（上限 3）。现在闸门一律用 `wipGateCount`。
- `K.refreshSlots` 里还有一层 `enforceCap`（每砍一轮重新数，直到真的不超）——那是**发资格**的兜底。

---

## 六、测试与工具（改完必跑）

| 命令 | 查什么 |
|---|---|
| `node tools/lua-compile.mjs` | 真编译（能抓 `for ... of` 这类真语法错） |
| `node tools/lua-test.mjs lua/test/logic_test.lua` | config + recipes（29 项） |
| `node tools/lua-test.mjs lua/test/kitchen_test.lua` | 后厨规则（39 项） |
| `node tools/lua-test.mjs lua/test/game_test.lua` | 端到端整局（12 项，机器人**绕过输入层**） |
| `node tools/lua-test.mjs lua/test/restore_test.lua` | ★还原契约（30 项）：点小票=流转、按键自动送票、tap/mash/hold 原版手感、名额 |
| `node tools/lua-test.mjs lua/test/e2e_key_test.lua` | ★★**全走按键路径**打一整局 + 按键无活率 + 名额硬上界 + 出餐链路 |
| `node tools/ui-oracle.mjs` | ★★**表现层判定**：逐帧读客户端控件树的真实文字，断言"有活时工位卡必须说要做什么"、"小票卡与工位卡判据一致"（这个缺口曾让显示 bug 活到真机） |
| `node tools/check-level-script.mjs` | ★ 验收"编辑器里的关卡存了哪一版脚本"（编辑器那份是内存副本，放文件≠生效） |
| `node tools/log-events.mjs --file=<日志>` | ★ 按发生顺序读真机日志（含 `[KTARGET]`/`[KDOWN]`/`[STATE]` 探针） |
| `node tools/layout-lint.mjs` | 框太矮 / 出界 / 忘上色 / Z 序 |
| `node tools/lua-test.mjs --entry=xuehuang --out=dist/xuehuang.lua` | 合成真机单文件 |
| `node tools/bundle-lint.mjs dist/xuehuang.lua` | 合成产物里的非 ASCII 是否都已转义 |
| `node tools/probe-bundle.mjs dist/xuehuang.lua --frames=N` | 在运行时里跑并打印**全部**日志（定位启动期错误） |
| `node tools/view-snap2.mjs --seconds=20 --out=preview/x.png` | 跑 N 秒 → 出**游戏画面**离线预览图 |
| `node tools/gil-inspect.mjs` / `backup-gil.mjs` | 关卡存档透视 / 改动前备份 |
| `node tools/design-shot.mjs [关键字]` | ★ 设计稿出图（`preview/design/*.html` → 同名 PNG）。**输出路径固定**、旧图自动进 `archive/出图历史/`；`--one <索引>` 单张出（跨进程安全） |
| `node tools/lua-test.mjs --entry=props_demo --out=dist/props_demo.lua` | 合成"实物视觉件"演示（杯子/炮筒/火） |
| `node tools/sim-run.mjs dist/props_demo.lua --frames=40 --json=dist/props.json` | 在模拟器里真建这三个视觉件，导出**控件树（绝对坐标）** |
| `node tools/props-render.mjs dist/props.json <out.png>` | ★ 把控件树画成 PNG —— **形状验收**就靠它（读我们自己的扁平导出格式，含旋转） |

> ⚠️ 视觉件是**嵌套**的（杯子下挂液体/斜条，火下挂 432 格）。`sim-run` 导出时
> **必须把子控件的相对坐标累加成绝对坐标**，否则渲染出来全叠在画布中心（踩过）。
> `D:/zuma/miliastra/tools/sim-render.mjs` 读的是**嵌套树**格式，对我们无效 —— 所以有了 `props-render.mjs`。

> ⚠️ `game_test.lua` 的机器人**直接调 kitchen**，所以它抓不到"按键没反应"这类问题 ——
> 那一类问题归 `e2e_key_test.lua`（它只经 `G.act`，与按键分支同一行代码）。

---

## 七、已知边界 / 待办

| 项 | 状态 |
|---|---|
| 拖拽小票指定工位 | ❌ 未做（平台上 Pointer 拖拽待验证）；现用"点小票 = 送到该去的工位"覆盖 |
| Esc 暂停 | 平台无 Esc 语义键 → 营业中用 `3` 代替 |
| 原版 A/S 开关键 | 平台无 A/S → 营业中用 `1` / `2` |
| 原版 B/C 工位键 | 平台无 B/C → 用 `Y` / `K`（语义对齐：四个工位各一键）。编辑器里可把奇匠按键改绑成 B/C |
| 9003 条 `[REJECT]` | 已消除（端到端实测按键无活率 0.0%）；探针仍保留，用 `showState=1` 可开 |
| 脚本变量 | `autoplay=1` 机器人代打（含自己开门）、`heartbeat=1` 心跳、`showState=1` 每秒工位状态、`showCounts=1` 控件计数；**临时**：`diag=0` 关诊断、`forceWrite=1` 每帧无视缓存强制写（见第八节） |

---

## 八、★ 写入链路诊断构建（2026-10-01 晚，临时）

**为什么有它**：真机现象"鼠标点正常、键盘按没反应；逻辑在走（`ok=true`）、画面不动"，本地全绿。
现在的头号嫌疑是**某次控件写入在真机上报错、被 `pcall` 吞掉，而 view 的缓存已经记成"写过了"**
⇒ 之后每帧都判"值没变"、直接 return ⇒ 画面永久停在那一帧。这一轮只做**让失败可见**，不改行为。

### 8.1 改了什么（全部是"观测"，无语义变化）

| 文件 | 观测点 |
|---|---|
| `lua/src/diag.lua` | 新增模块 `D`：`try` / `cacheSkip` / `note` / `boot` / `afterAct` / `summary`；构建标记 `xuehuang-diag-w1` |
| `lua/src/view.lua` | `setText` / `setStyle`（★ 唯一没有整数护栏的字号写入）+ 可见性：`menuVisible` / `boardVisible` / `menuBig` / `big` |
| `lua/src/host.lua` | `setFont`(字号/字色) / `setColor` / `setText` / `fitText`(尺寸/字号) / `setAlpha` / `setPos` / `setSize` / `show` / `hide` |
| `lua/src/xuehuang.lua` | `D.setup`（读 `diag`/`forceWrite`）、`afterAct` 里被吞的错误、`bootErr` 一行、`D.summary` 周期汇总 |

> `diag-write-path/写入点清单.md` 是逐字清单；**清单之外**追加了可见性写入
> （`H.show/H.hide`、`V.setBoardVisible/setMenuVisible`、菜单大字）—— 它们每帧都走，
> 且"SetVisible 被无声吞掉"在本项目**有前科**，所以一并纳入观测。

### 8.2 产物与判据

| 项 | 值 |
|---|---|
| 诊断产物 | `dist/xuehuang.diag.lua`（337472 字节，19 个模块，sha256 `630AD316…9FF9D36`） |
| 加密/转义 | `bundle-lint` 通过（字符串里的非 ASCII 全部 Lua 十进制转义） |
| 部署位置 | 关卡 `1073741825` 的 `external_lua_file/xuehuang.lua`（原文件已备份到 `dist/diag-w1-backup/`） |
| **关卡里是否跑上了诊断版** | `node tools/check-level-script.mjs` → 看 `xuehuang-diag-w1` 那一行；`.gil` 里嵌的脚本是**保存关卡那一刻的副本**，改了文件不保存 = 没生效 |
| 日志判据（全 ASCII） | `[DIAG] tag=… on=… forceWrite=…` / `[WERR] tag=… ctrl=… val=… err=…` / `[WERR-CACHE] …` / `[WERR-SUM] …` / `[BOOT] …` / `[SYNC] afterAct err=…` |

### 8.3 判定表（拿到真机日志后照这个看）

| 日志现象 | 结论 | 下一步 |
|---|---|---|
| `[BOOT] bootErr=…` | 启动就抛错 ⇒ `OnUpdate` 每帧提前 return | 按错误修启动路径 |
| `[SYNC] afterAct err=…` | 刷新函数本身在报错（以前被静默吞掉） | 修 `V.sync` |
| `[WERR] … err=integer expected` | 字号写了非整数 | 取整（`view.setStyle` 是唯一没护栏的点） |
| `[WERR-CACHE] …` | **确诊缓存投毒** | 写入失败时不要更新缓存 |
| 只有 `[WERR]`、无 `[WERR-CACHE]`、画面也不动 | 写入在失败但未闭环 | 先修那个 `tag`/`ctrl` |
| 一条错误都没有 + 画面仍不动 + `forceWrite=1` 也无效 | 真机确有未知规则 | 原样日志 + 产物交作者逐帧比对 |

`forceWrite=1` 是判定的关键一刀：画面恢复 ⇒ 病在缓存；仍不动 ⇒ 病在写入本身/目标控件。

### 8.4 回退

```bash
git checkout -- lua/src/view.lua lua/src/host.lua lua/src/xuehuang.lua tools/check-level-script.mjs
rm lua/src/diag.lua
# 关卡里的脚本要还原成线上版：把 dist/diag-w1-backup/<时间戳>/xuehuang.lua.before 放回
#   .../Beyond_Local_Save_Level/1073741825/external_lua_file/xuehuang.lua，再在编辑器里重新导入 + 保存关卡
```
> 另存一份完整改动补丁：`diag-write-path/w1-改动.patch`（可 `git apply` 复原）。

### 8.5 ★★ 本地已经把"缓存投毒"复现出来了（2026-10-01 晚，`probe-bundle` 90 行日志）

```
[DIAG] tag=xuehuang-diag-w1 on=true forceWrite=false
[BOOT] ok
[WERR] tag=view.setText ctrl=HudTip val=<非法 UTF-8> err=cannot convert invalid utf8 to javascript string
[WERR-EMIT] raw-print failed; ascii-only above          ← 诊断自己的 emit 一度把这条吞掉了
[WERR-CACHE] tag=view.setText ctrl=HudTip skipped=1 lastErr=cannot convert invalid utf8 ...
```

**根因（我们自己的代码，不是平台）**：

| 位置 | 代码 | 后果 |
|---|---|---|
| `view.lua:736-737` | `st.name:sub(1, 2)`（`st.name` 是中文，如 `捣锤区`） | `string.sub` 是**按字节**切的 ⇒ 切出半个汉字 ⇒ 字符串里带**非法 UTF-8 字节** |

写 `HudTip` 的值形如 `现在能按：H \xE6\x8D`（尾部 2 字节是半个 `捣`）⇒ 赋值时报错被 `pcall` 吞掉，
而 `txtCache` **已经记成"写过了"** ⇒ 下一帧同值直接被缓存跳过（`[WERR-CACHE]`）⇒ **这一行永久停住**。
这正是作者假设 A 的机制，**在本地第一次拿到了确凿的、可复现的实例**。

⚠️ 本轮**不修**（纪律：一次只改一个变量，先让真机说话）。真机跑完再看：
- 真机若也报（`[WERR] ... ctrl=HudTip`）⇒ 就是它，改成"按字符取前 2 个汉字"（如 `st.short`）；
- 真机若不报但提示行显示乱码/豆腐块 ⇒ 平台**不报错但画不出来**，同样要修这一处。

> 另一处同类字节切：`cup_tri_demo.lua:76` 的 `txt:sub(1, 6)`（演示脚本，非线上路径）。
> `view.lua` 的 `clip()` 是**按字符宽度**推进的，安全，可作为正确写法参考。

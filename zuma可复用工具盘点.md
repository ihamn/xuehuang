# D:\zuma 可复用工具盘点（给《雪皇的后厨》用）

> 侦查时间：2026-09-26（本机实测，不是照抄文档）
> 目的：新项目《雪皇的后厨：荒诞饮品模拟器》要上千星奇域，`D:\zuma` 里已经有一整套
> 「客户端 Lua 2D 玩法」的工具链**真跑通过**，这份文件回答三个问题：
> **有什么、现在还能不能跑、新项目该怎么取舍**。
> 标注：✅ = 本机刚实测过；⚠️ = 文档写着但本机没验；❌ = 本机实测环境的硬缺口。

---

## 零、一句话结论

| 结论 | 证据 |
|---|---|
| **能直接用**：本地无头跑整关 + 出 PNG 截图 + 控件预算账 + 单文件打包 + 节点图自检 + 环境/坐标/生命周期契约 | 见 §二 的 ✅ 行 |
| **有一个硬缺口**：`parity.mjs` / `test-lua.mjs` 需要**原生 Lua 解释器**，本机没有，`run-all` 因此有 2 步红 | §三 |
| **但缺口可以绕**：模拟器（Fengari）能跑整关，`run-all` 的 11/13 步是绿的；新项目只要**不碰 64 位整数**，本地闭环成立 | §三.3 |
| **最大的顺手工具**：`D:\miliastra-beyond-simulator` 社区模拟器（含 DSH 插件 + 技能 + agent 预设），能做「AI 直接搭 UI → 试玩 → 截图 → 断言」 | §四 |

---

## 一、怎么跑（本机实测命令）

```powershell
# 全量自检（13 步；本机 11 绿 2 红，红的两步是缺 Lua 解释器）
node D:\zuma\miliastra\tools\run-all.mjs

# 单跑一步：在假想的"千星客户端 Lua 运行时"里真跑我们的脚本 + 打印控件树
node D:\zuma\miliastra\tools\sim-play.mjs .\pc\hello.lua --frames=30
node D:\zuma\miliastra\tools\sim-play.mjs --level=1 --frames=90 --json=D:\moniji\_scratch\sim.json

# 把控件树画成 PNG（这就是"没有浏览器也能看见画面"的那条路）
node D:\zuma\miliastra\tools\sim-render.mjs <sim.json> <out.png>

# 把脚本放进游戏目录（云电脑重启后必跑一次）
node D:\zuma\miliastra\tools\pc-install-scripts.mjs
```

✅ **本机实测**：`hello.lua` 在模拟器里跑通（8 颗球 + 文本框出现）；
`out/zumaplus.lua` 整关跑通（**940 个控件 / 上限 1000，剩 60**，17 关菜单文案全在）；
`sim-render` 出图成功（见 `_scratch/menu.png`，65 KB，917 控件）。

---

## 二、工具清单（按"新项目用不用得上"排序）

| 工具 | 干什么 | 对新项目的价值 | 本机状态 |
|---|---|---|---|
| `tools/sim-play.mjs` | 用**社区千星客户端 Lua 运行时**（Fengari）真跑一遍脚本，打印日志 + 控件树 + 预算 | ★★★ **本地试玩台**。新项目的"点单→出餐"能不开游戏就验证 | ✅ 跑通 |
| `tools/sim-render.mjs` | 控件树 → PNG（Pillow 画的，位置/尺寸/颜色/字号/旋转/径向填充都来自运行时） | ★★★ **视觉验收**。小票框、工位区、按钮排版都能出图看 | ✅ 跑通 |
| `tools/lib/platform-limits.mjs` | 平台硬限制**写成代码**（每条带官方出处）+ `checkControlBudget()` | ★★★ 新项目控件预算账（雪皇要摆小票/工位/按钮，很容易超 1000） | ✅ |
| `tools/check-lua-sandbox.mjs` | 拦"千星没有的标准库"（`io.*`/`coroutine`/`string.dump`/`math.random`…） | ★★★ 换项目**只改路径常量**就能用；`math.random` 那条正好逼新项目走确定性随机 | ✅ 0 问题 |
| `tools/bundle-lua.mjs` | 多模块 → 单文件 Lua（含"生命周期要暴露成全局"这个坑） | ★★★ 上传用；新项目直接改 `ORDER` 列表 | ✅ |
| `tools/lib/lua-runner.mjs` | 找 Lua 解释器（多路径回退 + 版本标语），承载"手机端 noexec 要拷 TMPDIR"这类环境知识 | ★★ 要保留这个"环境问题要一眼看出来"的设计；**但本机找不到解释器**（§三） | ⚠️ 缺解释器 |
| `lua/host/mock.lua` | **假宿主** 41 KB：按真机契约封死字段白名单/只读字段/生命周期/点号调用 | ★★★ 这是整套工具里最值钱的一份。新项目**换业务 API 名**即可复用结构 | ⚠️ 没跑（需解释器） |
| `lua/test/test_mock.lua` / `test_bundle.lua` / `test_prefabs.lua` | 把上面那些契约写成**断言**（防止再犯"本地绿、真机炸"） | ★★★ 模板照抄 | ⚠️ 同上 |
| `lua/test/harness.lua` | 48 行极简测试框架（`ok/eq/near/truthy/finish`，`os.exit` 定退出码） | ★★ 直接用 | ⚠️ 同上 |
| `tools/run-all.mjs` | 13 步一条命令，退出码即结果（含"顺序很重要"的注释：**先导数据再打包**） | ★★ 新项目的 CI 骨架 | ✅/⚠️ 11 绿 2 红 |
| `tools/check-encoding.mjs` | 拦"被 PowerShell 写坏编码"的文本文件（中文 Windows 老坑） | ★★ 建议原样搬走 | ✅ 210 文件全合法 UTF-8 |
| `tools/pc-install-scripts.mjs` | 绕过编辑器的文件对话框，直接把 lua 写进 `external_lua_file` | ★★ 省几小时（见交接手册 §3.1） | ✅（未跑，逻辑清楚） |
| `tools/sim-play.mjs --probe=x.lua` | 跑完帧之后在**同一个 Lua 环境**里执行探针 | ★★ 出图看不出"模型里到底对不对"，靠它问 Lua 自己 | ✅ |
| `tools/check-graph.mjs` + `graph/` | TypeScript → `.gia` → 注入 `.gil` 的节点图工程（结算门：逃跑合法性/顺序/定时器，17 条断言） | ★★ **服务端逻辑**（计时/结算/遍历玩家）只能靠它，雪皇的"5 天计时/打烊结算"要用 | ✅ 17 条全过 |
| `graph/tools/read-gil-graphs.mjs` | 读 `.gil` 列出所有图 ID + 名字 + 节点数 | ★★ 解决"导入后图 ID 变了"这个必踩的坑 | ✅ |
| `tools/pack-pc.mjs` | 打包电脑端 zip（固定时间戳、产物字节稳定） | ★ 分发/给人试玩 | ✅ 110 KB 产物 |
| `tools/fetch-docs.mjs` + `ctx-grep.py` + `doc-section.py` | 抓 219 篇官方文档做离线快照；**带上下文**地 grep（官方文档一行一篇，直接 grep 会被截断） | ★★ 新项目查平台能力时不用再抓一次；`ctx-grep.py` 的"必须带上下文"是硬教训 | ⚠️ 未重跑（快照已在 `docs/official/`） |
| `tools/calc-balance.mjs` / `export-*.mjs` / `verify-export.mjs` | 数值导出 + 往返校验 + 平衡 sanity | ★ 雪皇可用同思路做"单量/冰度/糖度概率"与出餐时限的平衡校验 | ✅ |
| `tools/parity.mjs` + `lua/parity/run.lua` | JS↔Lua **逐值对拍**（81339 个数值零差异）+ `parity-diff.mjs` 定位第一处岔 |
| `tools/test-lua.mjs` | 跑 `lua/test/*.lua` | 上面两条需要原生 Lua（§三） |
| `tools/doc-section.py` / `lib/python.mjs` | 找一台**真的** Python 3（绕开 Windows Store 占位程序） | ★ 本机有 Python 3.12.1 + Pillow 12.1.0 ✅ | ✅ |
| `docs/official/md/*.md`（219 篇） | 官方文档离线可 grep 版 | ★★★ 雪皇要查的东西全在这：`客户端控件API文档`(51 KB)、`语音和文字聊天`、`命中检测`、`界面控件`、`全局计时器`、`关卡结算`、`多语言文本`、`千星沙箱`… | ✅ 在盘上 |
| `docs/04-移植规则清单.md` / `docs/05-移植方案.md` | 移植规则 + 施工图定稿 | ★★ 新项目"该怎么做才不返工"的直接前例 | ✅ |
| `.git`, `zuma.gil`, `zumaplus/` | 版本控制 / 关卡存档 / plus 分支 | ⚠️ 新项目另起仓库，别混进来 |

---

## 三、本机环境的硬缺口：没有原生 Lua 解释器

### 3.1 现象（✅ 实测）

`run-all` 的 **2 步红**，都是同一个原因：

```
=== parity.mjs —— JS<->Lua 对拍 ===   !! 退出码 1
=== test-lua.mjs —— Lua 侧测试 ===    !! 退出码 1
Error: 没找到 Lua 解释器。找过这些地方：
  D:\zuma\miliastra\vendor\bin\lua.exe（不存在）
  lua5.3 / lua53 / lua5.4 / lua54 / lua（跑不起来）
  C:\Users\netease\AppData\Local\Programs\Lua\bin\lua.exe（不存在）
```

其余 11 步全绿（导出/校验/沙箱/打包/节点图/**试玩台**/电脑端打包）。

### 3.2 为什么搞不到（都试过了）

| 路子 | 结果 |
|---|---|
| `choco install lua53` | ❌ `C:\ProgramData\chocolatey\lib-bad` 拒绝访问（需要管理员） |
| `vendor/lua53-choco.zip`（仓库里那份） | ❌ 只有 `.ignore` 占位 + 安装脚本，**里面没有 lua.exe** |
| `vendor/try-lua.zip`、`lua53-win64.zip` | ❌ 其实是 HTML 错误页（`<!doctype` 开头），不是 zip |
| lua.org 官方 Windows 二进制 | ❌ 404（官方不提供 Windows 二进制，只有源码 tar.gz） |
| SourceForge luabinaries（直链 + 3 个镜像） | ❌ 全都回 HTML 中介页（`<!doctype`） |
| 本机编译器（gcc/clang/cl/zig/make） | ❌ 一个都没有 → **不能自己编 Lua 源码** |
| 全盘找 lua.exe | ❌ 只有 `D:\MuMu Player 12\...\lua.dll`（模拟器自带的动态库，不是可执行解释器） |

⚠️ 但**网络是通的**：raw.githubusercontent / jsDelivr / npm registry / npmmirror 都能 200。
所以真要走通，有两条候选（都没在本轮落地）：
1. 用 npm 上的 **WASM 版 Lua** 当解释器（`wasmoon` 是 Lua 5.4 WASM；`lua-wasm` 这个包是 0.0.0 空壳）
   —— 需改 `lib/lua-runner.mjs` 的调用方式（现在是 `spawnSync(bin, [file])`）。
2. 找一份**可信的** lua 5.3 Windows 二进制放进 `vendor/bin/`（`lua-runner.mjs` 的第一优先候选就是这个路径）。

### 3.3 缺口怎么绕（关键判断）

**`sim-play.mjs` 不吃原生 Lua** —— 它跑的是社区模拟器（Fengari，JS 里的 Lua VM），✅ 本机实测整关跑通。
所以本地闭环是**成立的**，代价是：

> ⚠️ Fengari 的整数是 **32 位**（官方契约 §18 已确认这是已知底层限制）。
> zuma 的 `rng.lua` 靠 `& 0xFFFFFFFF` 做 32 位语义，在 Fengari 下 `0xFFFFFFFF == -1`，
> `rng.pick` 约一半取到 nil（球画成白色）。zuma 用"折回 [0,1)"兜住了不崩，但**序列不同**。

**对新项目的意思**：雪皇的随机点单（单量 1/2/3/4 杯、冰度、糖度）用**加权查表**就够，
**不要写 64 位整数运算**，就能让「本地模拟器 == 真机」这条线干净。
真要对拍（JS↔Lua 逐值），再补一个原生 Lua；不补也不阻塞 MVP。

---

## 四、顺手的大件：`D:\miliastra-beyond-simulator`（社区模拟器仓库）

这不是 zuma 的东西，但它就在本机、且**正是给千星 2D+Lua 项目用的**：

| 组件 | 是什么 | 对雪皇的价值 |
|---|---|---|
| `client/lua-runtime/` | Fengari 上的千星客户端 Lua 运行时（`runtime.js` 50 KB、`scene.js` 18 KB、`tween.js`）；含 `docs/observed-contract.md`（19 条真机契约，**比官方文档更硬**） | ★★★ 真机契约的权威来源；`sim-play.mjs` 就是挂它 |
| `skill/SKILL.md`（14.5 KB） | **千星沙箱 UI 模拟器使用技能**：五画布尺寸、控件 JSON 往返、试玩/截图/自动测试队列、服务器薄模拟、排障表 | ★★★ 写 Lua+UI 之前该先读这个 |
| `dsh-plugin/`（`qxqy-dsh-adapter`） | **DSH 插件**：`qxqy_studio_get/patch/play/ui_screenshot/play_screenshot/load` 一组工具，可让 AI 直接搭 UI、跑试玩、出截图、跑断言用例 | ★★★ 若装上，AI 能**闭环调 UI**（本会话**未安装**，183 个插件里没有它） |
| `agent/wonderland-lua-builder/` | agent 预设 + `qxqy-game-studio` 技能（`design-and-tests.md` / `workflow.md` / `prototype-art-playtest.md`） | ★★ 「先做原型+美术+试玩」的工序说明，正好是雪皇 MVP 的工序 |
| `mcp/` | MCP server（10 KB）暴露同一套能力 | ★ 给别的客户端用 |
| 五画布尺寸 | `pc-16-9` 1600×900 / `pc-21-9` 2100×900 / `mobile-16-9` 1280×720 / `mobile-19.5-9` 1560×720 / `mobile-4-3` 1280×960 | ★★★ **2D 布局基准是 mobile-16-9（1280×720）**，整屏构图必须在那看到；雪皇上手机，这条直接决定布局 |

⚠️ 与 `奇域实战经验-交接手册.md` §一 的口径差异（不是冲突，是两套场景）：
手册记的真机画布是 **1815×900**（云电脑/PC 实测），模拟器的预设是 **1600×900 等五种**。
**真机结论以真机为准**，模拟器/预设用来做本地布局与回归。

---

## 五、新项目能直接抄的六条（不是代码，是设计）

1. **控件池 + 只改属性**：`ui.lua` 把球/弹药/文字/光标区做成池子，运行期**只改位置/尺寸/颜色/可见性**，
   不新建不销毁（真机上"主屏控件、模板控件子节点不能动态创建"）。
   → 雪皇的**小票框、工位高亮、按钮**照这个做池子；控件预算按"每按钮 2 个（底+字）"算账。
2. **建的顺序 = 图层顺序**（真机实测）：**后建的盖在上面**，装饰先建、**文字最后建**。
   → 小票上的文字、工位上的状态字，必须最后建。
3. **三个开关**（`track`/`letters`/`fancy`）：每写一个新字段都是一次真机风险，
   炸了就改开关不用重打包。→ 雪皇的"制作动画/特效/学历提示"都该有这种开关。
4. **假宿主照真机契约封死**：字段白名单、只读字段、`Id` 大小写、`OnInit` 建不出控件、
   `EnableUpdate` 前没有 `OnUpdate`、`game` 点号调用。**这套断言的存在理由就是"本地绿、真机炸"**。
   → 雪皇的 `mock.lua` 第一版就该把这些抄进去。
5. **布局与命中共用一个公式**（`buttonRect` / `hitButton` 同源）：避免"看得见的按钮点不动"。
   → 雪皇的工位命中区、小票拖拽落点判定必须同源。
6. **平台硬限制写在代码里**：超了就导出报错，而不是等人去查文档。

---

## 六、给《雪皇的后厨》的落地建议（按风险排序）

| 序 | 事项 | 理由 |
|---|---|---|
| 1 | **先决定"必须联机吗"** | 路线 A（客户端 Lua）**只做单人**：联机信号延迟 ≥100ms 是硬边界。策划案里多人+语音是第二阶段、语音本身是平台能力（`mhaneb9qnvay_语音和文字聊天`）——**先按单人不联网做 MVP**，多人后续再评估 |
| 2 | 把「5 天 / 10 分钟」翻译成**全局计时器 + 服务端结算** | 客户端 `OnUpdate(dt)` 可以自己计时，但"打烊/胜负"建议走节点图（`graph/`），并牢记**结算前必须先设「逃跑合法性=是」**（否则一律记成逃跑） |
| 3 | 主画面按 **1280×720** 构图，PC 上等比放大留边 | 见 §四的布局基准 |
| 4 | 控件预算先算账再画 UI | 小票（步骤文字）+ 5 个工位 + HUD + 顾客反馈，很容易上百；上限 1000/组，且**每按钮按 2 个控件** |
| 5 | 随机点单用**加权查表 + 确定性随机** | 别用 `math.random`（沙箱检查会拦）；别用 64 位整数（Fengari 32 位，§三.3） |
| 6 | 从 `hello.lua` 抄起，**不要从 zuma.lua 抄** | zuma.lua 是 212 KB 的成品；`pc/hello.lua` 是"最小验证脚本"，专为打通管线写的 |
| 7 | 云电脑重启后先跑 `pc-install-scripts.mjs` | 会清空 `external_lua_file`（交接手册 §一 踩过两次） |
| 8 | 想让 AI 直接搭 UI/试玩/截图 → 装 `qxqy-dsh-adapter` | 本会话没装；装上后有一组 `qxqy_studio_*` 工具（需重启 `dsh web`） |

---

## 七、待办（本文件没做的事）

- [ ] 补一个可用的 Lua 解释器（WASM 或可信 5.3 二进制），让 `parity.mjs` / `test-lua.mjs` 变绿
- [ ] 决定是否安装 `qxqy-dsh-adapter` 插件（会改 profile，影响所有会话）
- [ ] 新项目脚手架：目录结构 + `platform-limits` + `check-encoding` + `mock.lua` 骨架 + `hello.lua` 对应物

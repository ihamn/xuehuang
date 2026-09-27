# 雪皇的后厨 · 千星奇域移植工具链

《雪皇的后厨：荒诞饮品模拟器》从网页（HTML/CSS/JS）移植到**原神千星奇域**（客户端 Lua + 客户端控件）的
完整工具链与工作区。**这个仓的价值在"工具链"**：它能在**没有游戏编辑器**的情况下，本地把脚本真跑起来、
出截图、做断言。

## 30 秒上手

```powershell
# 1) 在千星运行时里真跑一份脚本，打印日志 + 控件树（不需要打开游戏）
node tools/sim-run.mjs dist/props_demo.lua --frames=40 --json=dist/props.json

# 2) 把控件树画成 PNG（形状/布局验收靠它）
node tools/props-render.mjs dist/props.json preview/sim/props-sim.png

# 3) 逻辑测试（纯 Lua，跑在 Fengari 上）
node tools/lua-test.mjs --entry=xuehuang --out=dist/xuehuang.lua

# 4) 设计稿出图（HTML → PNG，输出路径固定、旧图自动归档）
node tools/design-shot.mjs
```

## 目录

| 目录 | 内容 |
|---|---|
| `lua/src/` | **游戏源码**（Lua）：`xuehuang.lua` 入口、`game/kitchen/state/order/day` 玩法、`view/skin/props` 表现、`input/host` 平台层 |
| `lua/test/` | 逻辑测试（纯 Lua，无需运行时） |
| `tools/` | **工具链**：跑脚本 / 出图 / 打包 / 静态检查 / 关卡存档透视 |
| `tests/` | 网页原型的测试（HTML 版对照） |
| `docs/` | 架构文档（**改东西前先读** `tech-architecture.md`） |
| `preview/design/` | 设计稿（网页稿 + PNG）；`preview/sim/` 是模拟器实建图 |
| `dist/` | 构建产物（单文件 Lua）+ 关卡存档备份 |
| `screenshots/` | 素材库/编辑器/真机截图（素材号实测证据） |
| `legacy/` | 早期 HTML 原型 |

## 核心工具

| 工具 | 作用 |
|---|---|
| `tools/sim-run.mjs` | 用社区运行时（Fengari 上的 Lua 5.3）**真跑**脚本，导出控件树（**绝对坐标**） |
| `tools/props-render.mjs` | 把控件树画成 PNG；**按素材号画对应图元**（方块/圆/三角/星/环） |
| `tools/lua-test.mjs` | 多模块 → 单文件 Lua（铺平，生命周期必须是全局函数） |
| `tools/design-shot.mjs` | 设计稿 HTML → PNG；输出路径固定、旧图自动进 `archive/出图历史/` |
| `tools/sheet.mjs` | 把主要出图拼成一张总览 |
| `tools/ui-oracle.mjs` | 逐帧读控件树文字，断言"显示与逻辑一致" |
| `tools/check-level-script.mjs` | 验收"编辑器里的关卡存了哪一版脚本"（放文件≠生效） |
| `tools/gil-*.mjs` | 关卡存档（`.gil`）透视 / 备份 |

## 已实测的平台事实（踩坑换来的，见 `docs/tech-architecture.md`）

1. **子控件坐标 = 相对父控件中心**的偏移（不是上沿）。
2. **父控件不裁子控件** —— 想让图形"被裁"只能用**同色遮挡块**；遮挡块背后不能有别的东西。
3. **三角形图元顶点朝上**，转 180° 才是尖朝下；**旋转要逐个控件设**，设到容器上会连带转整行。
4. **基础形状只有 6 个**：`100001` 方块 / `100002` 圆 / `100003` 三角 / `100004` 四角星 / `100005` 五角星 / `100006` 圆环。
   没有多边形、没有描边、没有渐变 → 梯形只能"**叠条**"或"**三角+遮挡**"凑。
5. **不要指望"旋转细条"能贴合斜边** —— 它绕自身中心转，和梯形边缘只在一个点吻合，会叠出第二个形状。
6. `math.random` 被沙箱拦 → 自带 LCG；`math.pow` 不存在 → 用 `^`。
7. **无头截图**跑"无限动画"页面会卡死/崩 Edge → 页面加 `#still` 定住一帧。

## 许可

自用项目。第三方参考：DOOM 火焰算法移植自
[filipedeschamps/doom-fire-algorithm](https://github.com/filipedeschamps/doom-fire-algorithm)（MIT）。

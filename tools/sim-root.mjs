// sim-root.mjs —— 「千星沙箱模拟器在哪」的**唯一一处**解析（所有工具共用）
//
// 为什么要它：原来 21 个工具各自写死 `D:/miliastra-beyond-simulator`，
//   于是这个工具链**只能在云电脑上跑** —— 换台机器（比如 Android/Termux）全部歇工，
//   而且换机器时只能手工去改 21 个文件。
//
// 找的顺序（第一个存在 `client/lua-runtime/src/index.js` 的胜出）：
//   1. 环境变量 XUEHUANG_SIM（沿用 tools/sim-run.mjs 早就定下的名字）
//   2. 仓内 third_party/beyond-sim      ← 非云电脑的机器放这儿（见 docs/本机运行环境.md）
//   3. D:/miliastra-beyond-simulator    ← 云电脑的老位置，保持原样不动
//   4. 仓的上一级目录同名文件夹         ← 历史上 sim-run.mjs 支持过的摆放
//
// 找不到时**不抛错**：各工具自己决定是"跳过"还是"报错"（多数老工具是跳过）。
import fs from 'node:fs';
import path from 'node:path';

export const ROOT = path.resolve(import.meta.dirname, '..');

const CANDIDATES = [
  process.env.XUEHUANG_SIM,
  path.join(ROOT, 'third_party', 'beyond-sim'),
  'D:/miliastra-beyond-simulator',
  path.resolve(ROOT, '..', 'miliastra-beyond-simulator'),
].filter(Boolean);

/** 判据：这个目录里有模拟器运行时的入口文件 */
const looksLikeSim = (dir) => Boolean(dir) && fs.existsSync(path.join(dir, 'client', 'lua-runtime', 'src', 'index.js'));

export const SIM_CANDIDATES = CANDIDATES;
export const SIM_ROOT = CANDIDATES.find(looksLikeSim) || CANDIDATES[CANDIDATES.length - 1];
export const SIM_FOUND = looksLikeSim(SIM_ROOT);

/** 运行时入口（createRuntime / walkControls / unpackRgba） */
export const SIM_ENTRY = path.join(SIM_ROOT, 'client', 'lua-runtime', 'src', 'index.js');
/** Fengari（模拟器自带的 Lua 5.3 解释器） */
export const SIM_FENGARI = path.join(SIM_ROOT, 'client', 'lua-runtime', 'node_modules', 'fengari', 'src', 'fengari.js');

/** 找不到时打印一行人话（工具照旧跳过，不要因为环境不齐就红一片） */
export function reportMissingSim(prefix = '模拟器') {
  console.log(`${prefix}：跳过（没找到 client/lua-runtime/src/index.js）`);
  console.log('  找过：\n    ' + CANDIDATES.join('\n    '));
  console.log('  可用 XUEHUANG_SIM=<模拟器根目录> 覆盖；云电脑默认 D:/miliastra-beyond-simulator');
}

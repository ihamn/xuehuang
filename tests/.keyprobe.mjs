// 按键体检：把 43 个奇匠按键（+抬起）全部绑上，按一下就把名字打到横幅上。
//   用途：搞清楚**真机上哪些键真的能收到事件**（有些键可能被游戏自己占用）。
//   开法：脚本变量 keyProbe=1
import fs from 'node:fs';
let v = fs.readFileSync('lua/src/xuehuang.lua', 'utf8');
if (v.includes('keyProbe')) { console.log('已存在 keyProbe，跳过'); process.exit(0); }

// ① 在 boot() 里，如果 keyProbe=1 就绑全部键
v = v.replace("    wireEvents()\n",
`    wireEvents()
    -- ★ 按键体检（keyProbe=1）：把全部奇匠按键绑上，按一下就把名字显示在横幅上
    if tonumber(tostring(H.param('keyProbe', 0))) ~= 0 then
      local H2 = require('host')
      local n = 0
      local names = {}
      pcall(function() for k in pairs(Enum.KeyEventType) do names[#names + 1] = tostring(k) end end)
      table.sort(names)
      local root2 = H2.root()
      for _, nm in ipairs(names) do
        local okE, ev = pcall(function() return Enum.KeyEventType[nm] end)
        if okE and ev then
          local okB = pcall(function()
            root2:AddKeyEventListener(ev, function()
              H2.setText(G.__probeText, nm)
              H2.show(G.__probeText)
              tip('按键: ' .. nm, 3)
              return true
            end)
          end)
          if okB then n = n + 1 end
        end
      end
      say('KEYPROBE 已绑定 %d 个按键事件（按任意奇匠键看横幅）', n)
    end
`);
fs.writeFileSync('lua/src/xuehuang.lua', v);
console.log('已注入 keyProbe');

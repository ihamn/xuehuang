import fs from 'node:fs';
let c = fs.readFileSync('lua/src/input.lua', 'utf8');
if (!c.includes('HITDBG')) {
  c = c.replace(`  if not ok or type(x) ~= 'number' then return false end`,
`  if not ok or type(x) ~= 'number' then return false end
  if IN.hitDbg then
    local H2 = require('host')
    H2.say('input', 'HITDBG click=(%.0f,%.0f) cx=%.0f cy=%.0f ctrl x=%.0f y=%.0f w=%.0f h=%.0f',
      IN.clicked.x, IN.clicked.y, cx, cy, x, y, w, h)
    IN.hitDbg = false
  end`);
  fs.writeFileSync('lua/src/input.lua', c);
  console.log('已加 HITDBG');
}

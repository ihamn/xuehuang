import fs from 'node:fs';
const txt = fs.readFileSync('lua/src/recipes.lua', 'utf8');
const blocks = txt.split(/\n  \{\n/).slice(1);
for (const b of blocks) {
  const id = (b.match(/id = '(\w+)'/) || [])[1];
  const name = (b.match(/name = '([^']+)'/) || [])[1];
  if (!id) continue;
  const stepsBlock = b.slice(b.indexOf('steps = {'));
  const steps = [...stepsBlock.matchAll(/\{\s*st = '(\w+)',\s*t = '([^']*)',\s*kind = '(\w+)'(,\s*taps = (\d+))?[^}]*\}/g)]
    .map(m => `${m[1]}/${m[3]}${m[5] ? '(x' + m[5] + ')' : ''} ${m[2].slice(0, 18)}`);
  const brewSteps = steps.filter(s => s.startsWith('brew'));
  if (brewSteps.length) {
    console.log(`  ${id} (${name}) 的 brew 步骤:`);
    for (const s of brewSteps) console.log('      ' + s);
  }
}
console.log('');
console.log('  所有 brew 步骤的手法统计:');
const kinds = {};
for (const m of txt.matchAll(/st = 'brew',\s*t = '[^']*',\s*kind = '(\w+)'/g)) kinds[m[1]] = (kinds[m[1]] || 0) + 1;
console.log('    ' + JSON.stringify(kinds));

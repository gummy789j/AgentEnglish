// Run inside a temporary Ghostty window and hold an unsent test prompt.
const [appPath, agent, cwd, done, scenario] = process.argv.slice(2);
const pty = require('../Bridge/node_modules/node-pty');
const path = require('node:path');
process.env.PATH=path.dirname(process.execPath)+':'+process.env.HOME+'/.local/bin:'+process.env.PATH;
const cmd=path.join(appPath,'Contents/Resources/Bridge/run.cjs');
const args = [cmd,agent,...(agent==='codex'?['-c','check_for_update_on_startup=false']:[])];
const p = pty.spawn(process.execPath,args,{cwd,cols:process.stdout.columns||80,rows:process.stdout.rows||25,env:{...process.env,TERM_PROGRAM:'ghostty',DISABLE_AUTOUPDATER:'1'}});
process.stdin.setRawMode(true);process.stdin.on('data',b=>p.write(b));p.onData(s=>process.stdout.write(s));
const sample = scenario === '--english' ? 'why the tests fails when the token expire?' : String.fromCodePoint(0x4f60, 0x597d);
setTimeout(()=>p.write('\x1b[200~'+sample+'\x1b[201~'),4500);
const fs=require('node:fs');let n=0;
const poll=setInterval(()=>{if(++n>180 || fs.existsSync(done)){clearInterval(poll);p.kill();setTimeout(()=>process.exit(0),300)}},250);

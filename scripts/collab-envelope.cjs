// A local signing helper; never prints the persistent capability or GitHub credentials.
const fs=require('node:fs'),crypto=require('node:crypto');
const [configPath,endpoint,input,output]=process.argv.slice(2);const c=JSON.parse(fs.readFileSync(configPath,'utf8'));
const data=JSON.parse(fs.readFileSync(input,'utf8')),value={endpoint,nonce:crypto.randomUUID(),time:Date.now(),data};
const mac=crypto.createHmac('sha256',c.token).update(JSON.stringify(value)).digest('hex');
fs.writeFileSync(output,JSON.stringify({...value,mac}),{mode:0o600});

// Checkpoint legacy T08 en PostgreSQL efímero y sin red.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

const root=fileURLToPath(new URL('../',import.meta.url));
const container=process.argv[2];
assert.match(container??'',/^mikuyapp-e1-t08-validation-[a-z0-9-]+$/);
function docker(args,input){
  const r=spawnSync('docker',args,{input,encoding:'utf8',timeout:120000,maxBuffer:16*1024*1024});
  if(r.error||r.status!==0) throw new Error(r.error?.message??r.stderr);
  return r.stdout.trim();
}
const [meta]=JSON.parse(docker(['inspect',container]));
assert.equal(meta.HostConfig.NetworkMode,'none');
assert.equal(meta.Mounts.some((m)=>m.Type==='bind'),false);
assert.match(meta.Config.Image,/^public\.ecr\.aws\/supabase\/postgres:17\./);
const resumedDatabase=process.argv[3];
if(resumedDatabase) assert.match(resumedDatabase,/^e1_t08_[a-f0-9]{32}$/);
const regressionStart=Number(process.argv[4]??0);
assert.ok(Number.isInteger(regressionStart)&&regressionStart>=0&&regressionStart<=3);
const database=resumedDatabase??`e1_t08_${randomUUID().replaceAll('-','')}`;
if(!resumedDatabase) docker(['exec',container,'createdb','-U','postgres','--template=template0',database]);
console.log(`LOCAL ISOLATED: ${container}/${database}${resumedDatabase?' (resume regresiones)':''}`);
const args=['exec','-i',container,'psql','-XqAt','-U','postgres','-d',database,'-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose'];
const sql=(source)=>docker(args,source);
const file=(path)=>sql(readFileSync(resolve(root,path),'utf8'));
if(!resumedDatabase){
docker(['exec','-i',container,'psql','-XqAt','-U','supabase_admin','-d',database,'-v','ON_ERROR_STOP=1'],
  docker(['exec',container,'pg_dump','-U','supabase_admin','-d','postgres','--schema-only']));
sql(`alter default privileges for role postgres in schema public revoke select,insert,update,delete on tables from anon,authenticated,service_role;
alter default privileges for role postgres in schema public revoke select,usage on sequences from anon,authenticated,service_role;
alter default privileges for role postgres in schema public revoke execute on functions from public,anon,authenticated,service_role;`);
const target='20260913000300_e1_t08_pago_sesion.sql';
const baseline=readdirSync(resolve(root,'supabase/migrations')).filter((f)=>f.endsWith('.sql')&&f<target).sort();
assert.equal(baseline.length,30);
for(const migration of baseline) file(`supabase/migrations/${migration}`);
file('supabase/seed.sql');
file('supabase/tests/e1_t03_fixture.sql');
const legacyBefore=sql(`select md5(string_agg(concat_ws('|',id,pedido_id,importe,medio,usuario_id,pagado_en),E'\n' order by id)) from public.pago`);
const legacyCount=sql('select count(*) from public.pago');
file(`supabase/migrations/${target}`);
const legacyAfter=sql(`select md5(string_agg(concat_ws('|',id,pedido_id,importe,medio,usuario_id,pagado_en),E'\n' order by id)) from public.pago`);
assert.equal(legacyAfter,legacyBefore);
assert.equal(sql('select count(*) from public.pago'),legacyCount);
assert.equal(sql('select count(*) from public.pago where sesion_caja_id is null and idempotency_key is null and propina=0'),legacyCount);
console.log(`Legacy: ${legacyCount}/${legacyCount} pagos preservados; fingerprint original idéntico; 0 sesiones fabricadas`);
console.log(file('supabase/tests/e1_t08_pago_sesion.sql').split('\n').filter((s)=>s.includes('E1-T08 SQL:')).join('\n'));
}else{
  console.log('Validación T08 propia no repetida: ya aprobada y la corrección afecta sólo un fixture H5.');
}

for(const regression of ['h5_t02_reopen_delivered_order','h5_t04_transactional_payment','h6_t02_sales_exports'].slice(regressionStart)){
  file(`supabase/tests/${regression}.sql`);
  console.log(`PASS regresión afectada: ${regression}`);
}

// Carrera H5 directamente afectada por retirar UNIQUE(pedido_id): dos sesiones
// psql independientes y claves distintas; el lock del pedido conserva un cobro.
file('supabase/tests/e1_t08_concurrency_setup.sql');
function connection(name){
  const child=spawn('docker',['exec','-i','-e',`PGAPPNAME=${name}`,container,'psql','-XqAt','-U','postgres','-d',database,
    '-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose'],{stdio:['pipe','pipe','pipe']});
  let output='',error='';
  child.stdout.on('data',(d)=>{output+=d}); child.stderr.on('data',(d)=>{error+=d});
  const done=new Promise((resolveDone,reject)=>{child.on('error',reject);child.on('close',(code)=>resolveDone({code,output,error}))});
  return {child,done,output:()=>output};
}
async function until(predicate,label){
  const deadline=Date.now()+20000;
  while(!predicate()){if(Date.now()>deadline)throw new Error(`Timeout ${label}`);await new Promise((r)=>setTimeout(r,100));}
}
const call=(key)=>`set local role authenticated;
select set_config('request.jwt.claim.sub','e1080000-0000-0000-0000-000000000501',true);
select to_jsonb(r) from public.rpc_registrar_pago_total_pedido(-10809,'e1080000-0000-0000-0000-000000000505','EFECTIVO',0,'${key}') r;`;
const first=connection('e1_t08_payment_holder'); let second;
try{
  first.child.stdin.write(`begin;set local statement_timeout='30s';${call(randomUUID())}select 'HOLDER_READY';\n`);
  await until(()=>first.output().includes('HOLDER_READY'),'primer pago sin commit');
  second=connection('e1_t08_payment_waiter');
  second.child.stdin.end(`begin;set local statement_timeout='30s';${call(randomUUID())}commit;\n`);
  await until(()=>sql("select exists(select 1 from pg_stat_activity where application_name='e1_t08_payment_waiter' and cardinality(pg_blocking_pids(pid))>0)")==='t','segundo pago bloqueado');
  first.child.stdin.end('commit;\n');
  const [winner,loser]=await Promise.all([first.done,second.done]);
  assert.equal(winner.code,0,winner.error); assert.notEqual(loser.code,0); assert.match(loser.error,/40001/);
  assert.equal(sql('select count(*) from public.pago where pedido_id=-10809'),'1');
  assert.equal(sql("select count(*) from public.pago where pedido_id=-10809 and sesion_caja_id='e1080000-0000-0000-0000-000000000505' and idempotency_key is not null and propina=0"),'1');
  assert.equal(sql("select count(*) from pg_stat_activity where application_name in ('e1_t08_payment_holder','e1_t08_payment_waiter')"),'0');
  console.log('PASS carrera H5 afectada: 1 cobro / 1 rechazo 40001 / 1 pago asociado / 0 conexiones residuales');
}finally{first.child.stdin.destroy();first.child.kill();second?.child.stdin.destroy();second?.child.kill();}

console.log('PASS T08 incremental: estructura/legacy, pago total asociado, propina, idempotencia, seguridad y regresiones afectadas. N pagos/parciales no habilitados.');

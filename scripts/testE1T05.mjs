// Validación incremental T05 en PostgreSQL local aislado y sin red.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

const root=fileURLToPath(new URL('../',import.meta.url));
const container=process.argv[2];
assert.match(container??'',/^mikuyapp-e1-t05-validation-[a-z0-9-]+$/);
function docker(args,input){
  const r=spawnSync('docker',args,{input,encoding:'utf8',timeout:120000,maxBuffer:16*1024*1024});
  if(r.error||r.status!==0) throw new Error(r.error?.message??r.stderr);
  return r.stdout.trim();
}
const [meta]=JSON.parse(docker(['inspect',container]));
assert.equal(meta.HostConfig.NetworkMode,'none');
assert.equal(meta.Mounts.some((m)=>m.Type==='bind'),false);
assert.match(meta.Config.Image,/^public\.ecr\.aws\/supabase\/postgres:17\./);
const database=`e1_t05_${randomUUID().replaceAll('-','')}`;
docker(['exec',container,'createdb','-U','postgres','--template=template0',database]);
console.log(`LOCAL ISOLATED: ${container}/${database}`);
const psql=['exec','-i',container,'psql','-XqAt','-U','postgres','-d',database,'-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose'];
const sql=(source)=>docker(psql,source);
const file=(path)=>sql(readFileSync(resolve(root,path),'utf8'));
docker(['exec','-i',container,'psql','-XqAt','-U','supabase_admin','-d',database,'-v','ON_ERROR_STOP=1'],
  docker(['exec',container,'pg_dump','-U','supabase_admin','-d','postgres','--schema-only']));
sql(`alter default privileges for role postgres in schema public revoke select,insert,update,delete on tables from anon,authenticated,service_role;
alter default privileges for role postgres in schema public revoke select,usage on sequences from anon,authenticated,service_role;
alter default privileges for role postgres in schema public revoke execute on functions from public,anon,authenticated,service_role;`);
const target='20260914000100_e1_t05_movimientos_cierre.sql';
const baseline=readdirSync(resolve(root,'supabase/migrations')).filter((f)=>f.endsWith('.sql')&&f<target).sort();
assert.equal(baseline.length,31);
for(const migration of baseline) file(`supabase/migrations/${migration}`);
file('supabase/seed.sql');
// Evidencia preexistente T04 para probar que ampliar auditoría no la reescribe.
sql(`insert into public.caja(local_id,codigo,nombre) select id,'T05-PRE','Pre T05' from public.local limit 1;
insert into public.sesion_caja(caja_id,local_id,abierta_por,monto_inicial,idempotency_key)
select c.id,c.local_id,p.id,7,'e1050000-0000-0000-0000-000000009001' from public.caja c
join public.perfil_usuario p on p.local_id=c.local_id join public.rol r on r.id=p.rol_id and r.codigo='CAJA'
where c.codigo='T05-PRE' limit 1;
insert into public.auditoria_caja(tipo,local_id,caja_id,sesion_caja_id,actor_id,monto_inicial,estado_anterior,estado_nuevo)
select 'APERTURA',s.local_id,s.caja_id,s.id,s.abierta_por,s.monto_inicial,null,'ABIERTA'
from public.sesion_caja s join public.caja c on c.id=s.caja_id where c.codigo='T05-PRE';`);
const auditBefore=sql(`select md5(string_agg(concat_ws('|',id,tipo,local_id,caja_id,sesion_caja_id,actor_id,creado_en,monto_inicial,estado_anterior,estado_nuevo),E'\n' order by id)) from public.auditoria_caja`);
file(`supabase/migrations/${target}`);
assert.equal(sql(`select md5(string_agg(concat_ws('|',id,tipo,local_id,caja_id,sesion_caja_id,actor_id,creado_en,monto_inicial,estado_anterior,estado_nuevo),E'\n' order by id)) from public.auditoria_caja`),auditBefore);
console.log('PASS compatibilidad: auditoría APERTURA T04 preservada exactamente');
console.log(file('supabase/tests/e1_t05_movimientos_cierre.sql').split('\n').filter((s)=>s.includes('E1-T05')).join('\n'));
file('supabase/tests/e1_t04_fixture.sql');
file('supabase/tests/e1_t04_apertura_sesion.sql');
console.log('PASS regresión directamente afectada: e1_t04_apertura_sesion');

file('supabase/tests/e1_t05_concurrency_setup.sql');
function connection(name){
  const child=spawn('docker',['exec','-i','-e',`PGAPPNAME=${name}`,container,'psql','-XqAt','-U','postgres','-d',database,
    '-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose'],{stdio:['pipe','pipe','pipe']});
  let output='',error=''; child.stdout.on('data',(d)=>{output+=d}); child.stderr.on('data',(d)=>{error+=d});
  const done=new Promise((resolveDone,reject)=>{child.on('error',reject);child.on('close',(code)=>resolveDone({code,output,error}))});
  return {child,done,output:()=>output};
}
async function until(predicate,label){const end=Date.now()+20000;while(!predicate()){if(Date.now()>end)throw new Error(`Timeout ${label}`);await new Promise((r)=>setTimeout(r,100));}}
const auth=(user)=>`set local role authenticated;select set_config('request.jwt.claim.sub','${user}',true);`;
async function race({label,holderSql,waiterSql,waiterName,verify}){
  const holder=connection(`e1_t05_${label}_holder`); let waiter;
  try{
    holder.child.stdin.write(`begin;set local statement_timeout='30s';${holderSql}select 'HOLDER_READY';\n`);
    await until(()=>holder.output().includes('HOLDER_READY'),`${label} holder`);
    waiter=connection(waiterName);
    waiter.child.stdin.end(`begin;set local statement_timeout='30s';${waiterSql}commit;\n`);
    await until(()=>sql(`select exists(select 1 from pg_stat_activity where application_name='${waiterName}' and cardinality(pg_blocking_pids(pid))>0)`)==='t',`${label} waiter bloqueado`);
    holder.child.stdin.end('commit;\n');
    const [winner,loser]=await Promise.all([holder.done,waiter.done]);
    assert.equal(winner.code,0,winner.error); assert.notEqual(loser.code,0); assert.match(loser.error,/40001/);
    verify();
    console.log(`PASS carrera ${label}: bloqueo real, ganador atómico y perdedor 40001`);
  }finally{holder.child.stdin.destroy();holder.child.kill();waiter?.child.stdin.destroy();waiter?.child.kill();}
}
const cajaA='e1055000-0000-0000-0000-000000000101', cajaB='e1055000-0000-0000-0000-000000000102';
await race({label:'doble-cierre',waiterName:'e1_t05_double_close_waiter',
  holderSql:`${auth(cajaA)}select public.rpc_cerrar_sesion_caja('e1055000-0000-0000-0000-000000000401',10,null,'${randomUUID()}');`,
  waiterSql:`${auth(cajaB)}select public.rpc_cerrar_sesion_caja('e1055000-0000-0000-0000-000000000401',10,null,'${randomUUID()}');`,
  verify:()=>{assert.equal(sql("select count(*) from public.resumen_cierre_sesion_caja where sesion_caja_id='e1055000-0000-0000-0000-000000000401'"),'1');assert.equal(sql("select count(*) from public.auditoria_caja where sesion_caja_id='e1055000-0000-0000-0000-000000000401' and tipo='CIERRE'"),'1');}});
await race({label:'cierre-vs-movimiento',waiterName:'e1_t05_close_move_waiter',
  holderSql:`${auth(cajaA)}select public.rpc_cerrar_sesion_caja('e1055000-0000-0000-0000-000000000402',20,null,'${randomUUID()}');`,
  waiterSql:`${auth(cajaB)}select public.rpc_registrar_movimiento_caja('e1055000-0000-0000-0000-000000000402','ENTRADA',5,'Concurrente','${randomUUID()}');`,
  verify:()=>{assert.equal(sql("select count(*) from public.movimiento_caja where sesion_caja_id='e1055000-0000-0000-0000-000000000402'"),'0');assert.equal(sql("select efectivo_esperado from public.sesion_caja where id='e1055000-0000-0000-0000-000000000402'"),'20.00');}});
await race({label:'cierre-vs-cobro',waiterName:'e1_t05_close_pay_waiter',
  holderSql:`${auth(cajaA)}select public.rpc_cerrar_sesion_caja('e1055000-0000-0000-0000-000000000403',30,null,'${randomUUID()}');`,
  waiterSql:`${auth(cajaB)}select to_jsonb(r) from public.rpc_registrar_pago_total_pedido(-10559,'e1055000-0000-0000-0000-000000000403','EFECTIVO',0,'${randomUUID()}') r;`,
  verify:()=>{assert.equal(sql('select count(*) from public.pago where pedido_id=-10559'),'0');assert.equal(sql("select estado from public.sesion_caja where id='e1055000-0000-0000-0000-000000000403'"),'CERRADA');assert.equal(sql('select estado from public.pedido where id=-10559'),'ENTREGADO');}});
assert.equal(sql("select count(*) from pg_stat_activity where application_name like 'e1_t05_%_holder' or application_name like 'e1_t05_%_waiter'"),'0');
console.log('PASS T05 incremental: TP13–TP18, TP09–TP10 aplicables y tres carreras reales.');

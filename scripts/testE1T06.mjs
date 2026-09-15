// Validación incremental T06 en PostgreSQL local aislado y sin red.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFileSync,readdirSync } from 'node:fs';
import { spawn,spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
const root=fileURLToPath(new URL('../',import.meta.url));const container=process.argv[2];
assert.match(container??'',/^mikuyapp-e1-t06-validation-[a-z0-9-]+$/);
function docker(args,input){const r=spawnSync('docker',args,{input,encoding:'utf8',timeout:120000,maxBuffer:20*1024*1024});if(r.error||r.status!==0)throw new Error(r.error?.message??r.stderr);return r.stdout.trim();}
const [meta]=JSON.parse(docker(['inspect',container]));assert.equal(meta.HostConfig.NetworkMode,'none');assert.equal(meta.Mounts.some(m=>m.Type==='bind'),false);assert.match(meta.Config.Image,/^public\.ecr\.aws\/supabase\/postgres:17\./);
const database=`e1_t06_${randomUUID().replaceAll('-','')}`;docker(['exec',container,'createdb','-U','postgres','--template=template0',database]);console.log(`LOCAL ISOLATED: ${container}/${database}`);
const args=['exec','-i',container,'psql','-XqAt','-U','postgres','-d',database,'-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose'];const sql=s=>docker(args,s);const file=p=>sql(readFileSync(resolve(root,p),'utf8'));
docker(['exec','-i',container,'psql','-XqAt','-U','supabase_admin','-d',database,'-v','ON_ERROR_STOP=1'],docker(['exec',container,'pg_dump','-U','supabase_admin','-d','postgres','--schema-only']));
sql(`alter default privileges for role postgres in schema public revoke select,insert,update,delete on tables from anon,authenticated,service_role;alter default privileges for role postgres in schema public revoke select,usage on sequences from anon,authenticated,service_role;alter default privileges for role postgres in schema public revoke execute on functions from public,anon,authenticated,service_role;`);
const target='20260914000200_e1_t06_descuento_pedido.sql';const baseline=readdirSync(resolve(root,'supabase/migrations')).filter(f=>f.endsWith('.sql')&&f<target).sort();assert.equal(baseline.length,32);for(const m of baseline)file(`supabase/migrations/${m}`);file('supabase/seed.sql');file('supabase/tests/e1_t03_fixture.sql');
const pedidoColumns=sql("select string_agg(column_name,',' order by ordinal_position) from information_schema.columns where table_schema='public' and table_name='pedido'");
file(`supabase/migrations/${target}`);assert.equal(sql("select string_agg(column_name,',' order by ordinal_position) from information_schema.columns where table_schema='public' and table_name='pedido'"),pedidoColumns);console.log('PASS DT-01: pedido sin snapshots/columnas duplicadas');
console.log(file('supabase/tests/e1_t06_descuento_pedido.sql').split('\n').filter(s=>s.includes('E1-T06 SQL:')).join('\n'));
for(const regression of ['e1_t08_pago_sesion','e1_t05_movimientos_cierre','h5_t04_transactional_payment','h6_t02_sales_exports']){file(`supabase/tests/${regression}.sql`);console.log(`PASS regresión directamente afectada: ${regression}`);}
file('supabase/tests/e1_t06_concurrency_setup.sql');
function connection(name){const child=spawn('docker',['exec','-i','-e',`PGAPPNAME=${name}`,container,'psql','-XqAt','-U','postgres','-d',database,'-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose'],{stdio:['pipe','pipe','pipe']});let output='',error='';child.stdout.on('data',d=>output+=d);child.stderr.on('data',d=>error+=d);const done=new Promise((resolve,reject)=>{child.on('error',reject);child.on('close',code=>resolve({code,output,error}))});return{child,done,output:()=>output};}
async function until(f,label){const end=Date.now()+20000;while(!f()){if(Date.now()>end)throw new Error(`Timeout ${label}`);await new Promise(r=>setTimeout(r,100));}}
const auth=u=>`set local role authenticated;select set_config('request.jwt.claim.sub','${u}',true);`;
const holder=connection('e1_t06_discount_holder');let payer;
try{
 holder.child.stdin.write(`begin;set local statement_timeout='30s';${auth('e1065000-0000-0000-0000-000000000102')}select public.rpc_decidir_descuento_pedido(-10659,'AUTORIZAR',null,'${randomUUID()}');select 'HOLDER_READY';\n`);
 await until(()=>holder.output().includes('HOLDER_READY'),'autorización sin commit');
 payer=connection('e1_t06_payment_waiter');payer.child.stdin.end(`begin;set local statement_timeout='30s';${auth('e1065000-0000-0000-0000-000000000101')}select to_jsonb(r) from public.rpc_registrar_pago_total_pedido(-10659,'e1065000-0000-0000-0000-000000000401','EFECTIVO',0,'${randomUUID()}') r;commit;\n`);
 await until(()=>sql("select exists(select 1 from pg_stat_activity where application_name='e1_t06_payment_waiter' and cardinality(pg_blocking_pids(pid))>0)")==='t','cobro bloqueado por descuento');
 holder.child.stdin.end('commit;\n');const [d,p]=await Promise.all([holder.done,payer.done]);assert.equal(d.code,0,d.error);assert.equal(p.code,0,p.error);
 assert.equal(sql('select importe from public.pago where pedido_id=-10659'),'80.00');assert.equal(sql("select concat_ws('|',estado,subtotal_base,importe_aplicado,total_neto) from public.descuento_pedido where pedido_id=-10659"),'AUTORIZADO|100.00|20.00|80.00');assert.equal(sql('select estado from public.pedido where id=-10659'),'PAGADO');assert.equal(sql('select count(*) from public.pago where pedido_id=-10659'),'1');
 assert.equal(sql("select count(*) from pg_stat_activity where application_name in ('e1_t06_discount_holder','e1_t06_payment_waiter')"),'0');console.log('PASS TP24 carrera real: cobro esperó autorización y usó neto 80; un pago consistente');
}finally{holder.child.stdin.destroy();holder.child.kill();payer?.child.stdin.destroy();payer?.child.kill();}
console.log('PASS T06 incremental: TP19–TP25 y regresiones directamente afectadas. Lock order definitivo queda pendiente de T09.');

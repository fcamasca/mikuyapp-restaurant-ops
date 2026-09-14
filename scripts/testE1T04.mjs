// Validación T04 exclusivamente local, sin .env, URLs remotas ni datos alojados.
import assert from 'node:assert/strict';
import { randomUUID, createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const container = process.argv[2];
assert.match(container ?? '', /^mikuyapp-e1-t04-validation-[a-z0-9-]+$/);
function docker(args, input) {
  const result = spawnSync('docker', args, { input, encoding: 'utf8', timeout: 120_000, maxBuffer: 16 * 1024 * 1024 });
  if (result.error || result.status !== 0) throw new Error(result.error?.message ?? result.stderr);
  return result.stdout.trim();
}
const t03Hashes = {
  'scripts/testE1T03.mjs': '0C59F1A6BA5CD14274CE4094296062BE806F78936FFA82F7B070648B1A668831',
  'supabase/migrations/20260913000100_e1_t03_caja_sesion.sql': '9186C04D274C14ED6004A7446C360A37E735A275EC9C2996A4FE3AB8316F7F64',
  'supabase/tests/e1_t03_caja_sesion.sql': '8EBABA4881C6B6A9C26F8CFDF8B31ACAA5D8C2C6DC24608D87DEF999B9B01750',
  'supabase/tests/e1_t03_fixture.sql': '376F83BAFA571A857DED0C4A408B1D534156FEDF1160EDDA0E87063690431F51',
  'specs/E1-CashOperation/implementation-t03.md': 'E1E190EEBC6C1FF3085FE5F3B09B4BF3460386459E308D3C84F3C716EE2A3426',
};
for (const [path, hash] of Object.entries(t03Hashes)) {
  // Normalización LF permite checkout CRLF sin cambiar el contenido aprobado.
  const actual = createHash('sha256').update(readFileSync(resolve(root, path), 'utf8').replaceAll('\r\n', '\n')).digest('hex').toUpperCase();
  assert.equal(actual, hash, `T03 debe permanecer intacta: ${path}`);
}
console.log('T03 preservada: 5/5 SHA-256 de migración, pruebas y evidencia');
const [metadata] = JSON.parse(docker(['inspect', container]));
assert.equal(metadata.HostConfig.NetworkMode, 'none');
assert.match(metadata.Config.Image, /^public\.ecr\.aws\/supabase\/postgres:17\./);
assert.equal(metadata.Mounts.some((m) => m.Type === 'bind'), false);
assert.equal(docker(['exec', container, 'psql', '-XAt', '-U', 'postgres', '-d', 'postgres', '-c',
  "select count(*) from pg_class where relnamespace='public'::regnamespace and relkind in ('r','p')"]), '0');
const database = `e1_t04_${randomUUID().replaceAll('-', '')}`;
docker(['exec', container, 'createdb', '-U', 'postgres', '--template=template0', database]);
console.log(`LOCAL ISOLATED: ${container}/${database}`);
const psqlArgs = ['exec', '-i', container, 'psql', '-XqAt', '-U', 'postgres', '-d', database, '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose'];
const sql = (source) => docker(psqlArgs, source);
const file = (path) => sql(readFileSync(resolve(root, path), 'utf8'));
docker(['exec', '-i', container, 'psql', '-XqAt', '-U', 'supabase_admin', '-d', database, '-v', 'ON_ERROR_STOP=1'],
  docker(['exec', container, 'pg_dump', '-U', 'supabase_admin', '-d', 'postgres', '--schema-only']));
// Defaults equivalentes a no auto-exposición Data API en config.toml, sólo aquí.
sql(`alter default privileges for role postgres in schema public revoke select,insert,update,delete on tables from anon,authenticated,service_role;
  alter default privileges for role postgres in schema public revoke select,usage on sequences from anon,authenticated,service_role;
  alter default privileges for role postgres in schema public revoke execute on functions from public,anon,authenticated,service_role;`);
const migration = '20260913000200_e1_t04_apertura_sesion.sql';
const baseline = readdirSync(resolve(root, 'supabase/migrations')).filter((f) => f.endsWith('.sql') && f < migration).sort();
assert.equal(baseline.length, 29);
for (const name of baseline) file(`supabase/migrations/${name}`);
file('supabase/seed.sql');
file('supabase/tests/e1_t03_fixture.sql');
file('supabase/tests/e1_t04_fixture.sql');
const originalTables = ['local', 'rol', 'perfil_usuario', 'mesa', 'categoria', 'producto', 'pedido', 'detalle_pedido', 'historial_estado', 'pago', 'caja', 'sesion_caja'];
const fingerprints = () => originalTables.map((t) => sql(`select md5(coalesce(string_agg(row_to_json(r)::text,'' order by row_to_json(r)::text),'')) from public.${t} r;`));
const before = fingerprints();
const oldSession = sql("select row_to_json(s) from public.sesion_caja s where id='e1040000-0000-0000-0000-000000000201'");
file(`supabase/migrations/${migration}`);
assert.deepEqual(fingerprints(), before);
console.log('Migración T04 aplicada: 12/12 tablas preexistentes sin cambios de datos');
console.log(file('supabase/tests/e1_t04_apertura_sesion.sql').split('\n').filter((s) => s.includes('E1-T04 SQL:')).join('\n'));
assert.deepEqual(fingerprints(), before, 'Los tests SQL revierten sus fixtures operativos');

function connection(name, user = 'postgres') {
  const child = spawn('docker', ['exec', '-i', '-e', `PGAPPNAME=${name}`, container, 'psql', '-XqAt', '-U', user, '-d', database,
    '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose'], { stdio: ['pipe', 'pipe', 'pipe'] });
  let output = ''; let error = '';
  child.stdout.on('data', (d) => { output += d; });
  child.stderr.on('data', (d) => { error += d; });
  const done = new Promise((resolveDone, reject) => {
    child.on('error', reject);
    child.on('close', (code) => resolveDone({ code, output, error }));
  });
  return { child, done, output: () => output };
}
async function until(predicate, label) {
  const deadline = Date.now() + 20_000;
  while (!predicate()) {
    if (Date.now() > deadline) throw new Error(`Timeout: ${label}`);
    await new Promise((r) => setTimeout(r, 100));
  }
}
const actorA = 'e1040000-0000-0000-0000-000000000011';
const actorB = 'e1040000-0000-0000-0000-000000000012';
const local = 'e1040000-0000-0000-0000-000000000001';
const auth = (actor) => `set local role authenticated; select set_config('request.jwt.claim.sub','${actor}',true);`;
const rpc = (caja, key, amount) => `select public.rpc_abrir_sesion_caja('${caja}',${amount},'${key}');`;
for (const [index, mode] of ['different-actors', 'same-key', '23505-fallback'].entries()) {
  const caja = `e1040000-0000-0000-0000-00000000010${6 + index}`;
  const firstKey = randomUUID();
  const secondKey = mode === 'same-key' ? firstKey : randomUUID();
  const secondActor = mode === 'same-key' ? actorA : actorB;
  const first = connection(`e1_t04_holder_${index}`, mode === '23505-fallback' ? 'supabase_admin' : 'postgres');
  let second;
  try {
    let firstCommand = auth(actorA) + rpc(caja, firstKey, 10);
    if (mode === '23505-fallback') {
      // Escritor privilegiado de fixture que omite el protocolo de locks/FK para
      // alcanzar REALMENTE el índice mientras la RPC no puede ver su INSERT.
      // Sólo su transacción efímera usa replica; no altera triggers del esquema.
      firstCommand = `set local session_replication_role=replica;
        insert into public.sesion_caja(caja_id,local_id,abierta_por,monto_inicial,idempotency_key)
        values('${caja}','${local}','${actorA}',10,'${firstKey}') returning to_jsonb(sesion_caja);
        insert into public.auditoria_caja(tipo,local_id,caja_id,sesion_caja_id,actor_id,creado_en,monto_inicial,estado_nuevo)
        select 'APERTURA',local_id,caja_id,id,abierta_por,abierta_en,monto_inicial,'ABIERTA' from public.sesion_caja where caja_id='${caja}';`;
    }
    first.child.stdin.write(`begin; set local statement_timeout='30s'; ${firstCommand} select 'HOLDER_READY';\n`);
    await until(() => first.output().includes('HOLDER_READY'), mode + ' holder');
    second = connection(`e1_t04_waiter_${index}`);
    second.child.stdin.end(`begin; set local statement_timeout='30s'; ${auth(secondActor)}${rpc(caja, secondKey, mode === 'same-key' ? 10 : 70)}commit;\n`);
    await until(() => sql(`select exists(select 1 from pg_stat_activity where application_name='e1_t04_waiter_${index}' and cardinality(pg_blocking_pids(pid))>0)`) === 't', mode + ' bloqueo real');
    first.child.stdin.end('commit;\n');
    const outcomes = await Promise.all([first.done, second.done]);
    for (const result of outcomes) assert.equal(result.code, 0, result.error);
    const results = outcomes.map((r) => JSON.parse(r.output.split('\n').find((s) => s.startsWith('{'))));
    assert.equal(results[0].id, results[1].id);
    assert.equal(results[1].abierta_por, actorA);
    assert.equal(results[1].monto_inicial, 10);
    assert.equal(sql(`select count(*) from public.sesion_caja where caja_id='${caja}' and estado='ABIERTA'`), '1');
    assert.equal(sql(`select count(*) from public.auditoria_caja where caja_id='${caja}'`), '1');
    assert.equal(sql(`select count(*) from public.solicitud_apertura_caja where caja_id='${caja}'`), mode === 'different-actors' ? '2' : '1');
    assert.equal(sql(`select count(*) from pg_stat_activity where application_name in ('e1_t04_holder_${index}','e1_t04_waiter_${index}')`), '0');
    console.log(`PASS carrera ${mode}: 2 respuestas exitosas, mismo id, 1 ABIERTA, 1 auditoría, 0 conexiones residuales`);
  } finally {
    first.child.stdin.destroy(); first.child.kill();
    second?.child.stdin.destroy(); second?.child.kill();
  }
}
const regressions = [
  'h3_t01_model', 'h3_t02_open_or_recover_order', 'h3_t03_add_order_detail', 'h3_t04_open_order_detail_mutations',
  'h3_t05_send_order_to_kitchen', 'release_empty_order_table', 'order_audit_trail', 'h4_t01_order_detail_sent_at',
  'h4_t02_kitchen_board_snapshot', 'h4_t03_kitchen_detail_state_transition', 'h4_t04_derived_order_table_state',
  'h4_t05_realtime_publication_rls', 'h5_t02_safe_order_delivery', 'h5_t02_reopen_delivered_order',
  'h5_t03_cashier_pending_orders_read', 'h5_t04_transactional_payment', 'h5_t06_realtime_cashier_signal',
  'h6_t02_sales_exports', 'dbstd_t02_authenticated_context_hardening', 'dbstd_t03_function_metadata',
  'dbstd_t04_catalog_comments', 'domain_object_names',
];
for (const name of regressions) { file(`supabase/tests/${name}.sql`); console.log(`PASS regression SQL: ${name}`); }
assert.deepEqual(fingerprints().slice(0, 11), before.slice(0, 11));
assert.equal(sql("select row_to_json(s) from public.sesion_caja s where id='e1040000-0000-0000-0000-000000000201'"), oldSession);
console.log(`PASS T04: 3 carreras + ${regressions.length} suites SQL; legacy/T03 preservados; sin DEV alojado ni PROD.`);

// Sólo PostgreSQL Supabase local efímero. No lee .env ni acepta URL de conexión.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const container = process.argv[2];
assert.match(container ?? '', /^mikuyapp-e1-t03-validation-[a-z0-9-]+$/);
function docker(args, input) {
  const result = spawnSync('docker', args, { input, encoding: 'utf8', timeout: 120_000, maxBuffer: 16 * 1024 * 1024 });
  if (result.error || result.status !== 0) throw new Error(result.error?.message ?? result.stderr);
  return result.stdout.trim();
}
const [metadata] = JSON.parse(docker(['inspect', container]));
assert.equal(metadata.HostConfig.NetworkMode, 'none', 'Se exige aislamiento de red');
assert.match(metadata.Config.Image, /^public\.ecr\.aws\/supabase\/postgres:17\./);
assert.equal(metadata.Mounts.some((mount) => mount.Type === 'bind'), false, 'No se permiten bind mounts');
assert.equal(docker(['exec', container, 'psql', '-XAt', '-U', 'postgres', '-d', 'postgres', '-c',
  "select count(*) from pg_class where relnamespace = 'public'::regnamespace and relkind in ('r','p')"]), '0',
  'La plantilla postgres debe estar vacía; nunca usar una base de aplicación');

const database = `e1_t03_${randomUUID().replaceAll('-', '')}`;
docker(['exec', container, 'createdb', '-U', 'postgres', '--template=template0', database]);
console.log(`LOCAL ISOLATED: ${container}/${database}`);
const psqlArgs = ['exec', '-i', container, 'psql', '-XqAt', '-U', 'postgres', '-d', database, '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose'];
const sql = (source) => docker(psqlArgs, source);
// Copia sólo el bootstrap vacío de la imagen (auth.uid, roles ya existentes,
// extensiones), sin datos. No requiere desconectar workers internos de Supabase.
docker(['exec', '-i', container, 'psql', '-XqAt', '-U', 'supabase_admin', '-d', database, '-v', 'ON_ERROR_STOP=1'],
  docker(['exec', container, 'pg_dump', '-U', 'supabase_admin', '-d', 'postgres', '--schema-only']));
const file = (relative) => sql(readFileSync(resolve(root, relative), 'utf8'));
// La CLI del proyecto desactiva auto-exposición Data API; la imagen PostgreSQL
// sola conserva los defaults legacy. Reproducir config.toml sólo en esta base.
sql(`alter default privileges for role postgres in schema public
       revoke select, insert, update, delete on tables from anon, authenticated, service_role;
     alter default privileges for role postgres in schema public
       revoke select, usage on sequences from anon, authenticated, service_role;
     alter default privileges for role postgres in schema public
       revoke execute on functions from public, anon, authenticated, service_role;`);
const migrations = readdirSync(resolve(root, 'supabase/migrations')).filter((name) => name.endsWith('.sql')).sort();
const migration = '20260913000100_e1_t03_caja_sesion.sql';
const baseline = migrations.filter((name) => name < migration);
assert.equal(baseline.length, 28, 'Revisar baseline si se agregan migraciones anteriores');
for (const name of baseline) file(`supabase/migrations/${name}`);
console.log(`Baseline: ${baseline.length} migraciones aplicadas`);
file('supabase/seed.sql');
file('supabase/tests/e1_t03_fixture.sql');
const legacyTables = ['local', 'rol', 'perfil_usuario', 'mesa', 'categoria', 'producto', 'pedido', 'detalle_pedido', 'historial_estado', 'pago'];
const fingerprints = () => legacyTables.map((table) => sql(`select md5(coalesce(string_agg(row_to_json(r)::text, '' order by row_to_json(r)::text), '')) from public.${table} r;`));
const before = fingerprints();
file('supabase/tests/dbstd_t03_function_metadata.sql');
console.log('Baseline grants DBSTD: fingerprint histórico confirmado');
file(`supabase/migrations/${migration}`);
assert.deepEqual(fingerprints(), before, 'Las 10 tablas legacy deben conservar todas sus filas/campos');
console.log('Migración T03: aplicada; 10/10 fingerprints legacy idénticos');
console.log(file('supabase/tests/e1_t03_caja_sesion.sql').split('\n').filter((line) => line.includes('E1-T03 SQL:')).join('\n'));

// Conexiones independientes y barrera real: el segundo INSERT debe estar bloqueado
// en el índice único antes de confirmar la transacción que ya insertó la sesión.
function connection(name) {
  const child = spawn('docker', ['exec', '-i', '-e', `PGAPPNAME=${name}`, container,
    'psql', '-XqAt', '-U', 'postgres', '-d', database, '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose'],
  { stdio: ['pipe', 'pipe', 'pipe'] });
  let output = ''; let error = '';
  child.stdout.on('data', (data) => { output += data; });
  child.stderr.on('data', (data) => { error += data; });
  const done = new Promise((resolveDone, reject) => {
    child.on('error', reject);
    child.on('close', (code) => resolveDone({ code, output, error }));
  });
  return { child, done, output: () => output };
}
async function until(predicate, label) {
  const deadline = Date.now() + 15_000;
  while (!predicate()) {
    if (Date.now() >= deadline) throw new Error(`Timeout: ${label}`);
    await new Promise((resolveWait) => setTimeout(resolveWait, 100));
  }
}
const insert = `insert into public.sesion_caja (caja_id, local_id, abierta_por, monto_inicial, idempotency_key)
 select id, local_id, 'e1030000-0000-0000-0000-000000000011', 10, gen_random_uuid()
 from public.caja where local_id = 'e1030000-0000-0000-0000-000000000001';`;
const first = connection('e1_t03_holder');
let second;
try {
  first.child.stdin.write(`begin; ${insert} select 'HOLDER_READY';\n`);
  await until(() => first.output().includes('HOLDER_READY'), 'primera inserción sin commit');
  second = connection('e1_t03_competitor');
  second.child.stdin.end(insert);
  await until(() => sql("select exists(select 1 from pg_stat_activity where application_name = 'e1_t03_competitor' and cardinality(pg_blocking_pids(pid)) > 0)") === 't', 'segunda conexión bloqueada realmente');
  first.child.stdin.end('commit;\n');
  const outcomes = await Promise.all([first.done, second.done]);
  assert.equal(outcomes[0].code, 0, outcomes[0].error);
  assert.notEqual(outcomes[1].code, 0);
  assert.match(outcomes[1].error, /23505/);
  assert.equal(sql("select count(*) from public.sesion_caja where estado = 'ABIERTA'"), '1');
  assert.equal(sql("select count(*) from pg_stat_activity where application_name in ('e1_t03_holder','e1_t03_competitor')"), '0');
  console.log('Concurrencia índice T03: 1 commit / 1 rechazo 23505; 1 ABIERTA; 0 conexiones residuales');
} finally {
  first.child.stdin.destroy(); first.child.kill();
  second?.child.stdin.destroy(); second?.child.kill();
}

const regressions = [
  'h3_t01_model', 'h3_t02_open_or_recover_order', 'h3_t03_add_order_detail',
  'h3_t04_open_order_detail_mutations', 'h3_t05_send_order_to_kitchen',
  'release_empty_order_table', 'order_audit_trail', 'h4_t01_order_detail_sent_at',
  'h4_t02_kitchen_board_snapshot', 'h4_t03_kitchen_detail_state_transition',
  'h4_t04_derived_order_table_state', 'h4_t05_realtime_publication_rls',
  'h5_t02_safe_order_delivery', 'h5_t02_reopen_delivered_order',
  'h5_t03_cashier_pending_orders_read', 'h5_t04_transactional_payment',
  'h5_t06_realtime_cashier_signal', 'h6_t02_sales_exports',
  'dbstd_t02_authenticated_context_hardening',
  'dbstd_t03_function_metadata', 'dbstd_t04_catalog_comments', 'domain_object_names',
];
for (const name of regressions) {
  file(`supabase/tests/${name}.sql`);
  console.log(`PASS SQL regression: ${name}`);
}
assert.deepEqual(fingerprints(), before, 'La regresión transaccional no debe alterar filas legacy');
console.log(`PASS: SQL T03 + 1 carrera estructural + ${regressions.length} suites SQL de regresión. Base retenida para inspección; no se toca DEV alojado/PROD.`);

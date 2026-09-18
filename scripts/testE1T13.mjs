import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const container = process.argv[2];
assert.match(container ?? '', /^mikuyapp-e1-t09-validation-[a-z0-9-]+$/);

function docker(args, input) {
  const result = spawnSync('docker', args, {
    input,
    encoding: 'utf8',
    timeout: 120_000,
    maxBuffer: 32 * 1024 * 1024,
  });
  if (result.error || result.status !== 0) {
    throw new Error(result.error?.message ?? result.stderr);
  }
  return result.stdout.trim();
}

const [metadata] = JSON.parse(docker(['inspect', container]));
assert.equal(metadata.HostConfig.NetworkMode, 'none');
assert.equal(metadata.Mounts.some((mount) => mount.Type === 'bind'), false);
assert.match(metadata.Config.Image, /^public\.ecr\.aws\/supabase\/postgres:17\./);

const database = `e1_t13_${randomUUID().replaceAll('-', '')}`;
docker(['exec', container, 'createdb', '-U', 'postgres', '--template=template0', database]);
console.log(`LOCAL ISOLATED: ${container}/${database}`);

const psqlArgs = ['exec', '-i', container, 'psql', '-XqAt', '-U', 'postgres', '-d', database,
  '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose'];
const sql = (source) => docker(psqlArgs, source);
const file = (path) => sql(readFileSync(resolve(root, path), 'utf8'));

docker(
  ['exec', '-i', container, 'psql', '-XqAt', '-U', 'supabase_admin', '-d', database,
    '-v', 'ON_ERROR_STOP=1'],
  docker(['exec', container, 'pg_dump', '-U', 'supabase_admin', '-d', 'postgres', '--schema-only']),
);
sql('alter default privileges for role postgres in schema public revoke select,insert,update,delete on tables from anon,authenticated,service_role; alter default privileges for role postgres in schema public revoke select,usage on sequences from anon,authenticated,service_role; alter default privileges for role postgres in schema public revoke execute on functions from public,anon,authenticated,service_role;');

const migrations = readdirSync(resolve(root, 'supabase/migrations'))
  .filter((name) => name.endsWith('.sql'))
  .sort();
for (const migration of migrations) file(`supabase/migrations/${migration}`);
file('supabase/seed.sql');

assert.equal(migrations.at(-1), '20260918000300_e1_delta_t12_reportes_cobro.sql');
assert.match(sql("select pg_get_functiondef('public.tgf_bloquear_detalle_pedido_con_pago()'::regprocedure)"), /security definer/i);
assert.match(sql("select pg_get_functiondef('public.rpc_registrar_cobro_pedido(bigint,uuid,text,jsonb,uuid)'::regprocedure)"), /sesion_caja[\s\S]*for update[\s\S]*pedido[\s\S]*for update[\s\S]*mesa[\s\S]*for update/i);
assert.match(sql("select pg_get_functiondef('public.rpc_registrar_pago_pedido_v2(bigint,uuid,numeric,text,numeric,uuid)'::regprocedure)"), /rpc_registrar_cobro_pedido/i);
console.log(`PASS replay limpio final ${migrations.length} migraciones; seed aplicado; delta T09-T13 presente.`);
console.log(`DATABASE=${database}`);

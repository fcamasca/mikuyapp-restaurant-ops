import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";

const root = fileURLToPath(new URL("../", import.meta.url));
const container = process.argv[2] ?? "supabase_db_mikuyapp-restaurant-ops";
assert.match(container, /^supabase_db_[a-z0-9_-]+$/);

function docker(args, input) {
  const result = spawnSync("docker", args, { input, encoding: "utf8", timeout: 180_000, maxBuffer: 64 * 1024 * 1024 });
  if (result.error || result.status !== 0) throw new Error(result.error?.message ?? result.stderr);
  return result.stdout.trim();
}

const database = `e1_t16_${randomUUID().replaceAll("-", "")}`;
docker(["exec", container, "createdb", "-U", "postgres", "--template=template0", database]);
console.log(`LOCAL ISOLATED: ${container}/${database}`);
const psql = ["exec", "-i", container, "psql", "-XqAt", "-U", "postgres", "-d", database, "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose"];
const sql = (source) => docker(psql, source);
const file = (path) => sql(readFileSync(resolve(root, path), "utf8"));

docker(["exec", "-i", container, "psql", "-XqAt", "-U", "supabase_admin", "-d", database, "-v", "ON_ERROR_STOP=1"], docker(["exec", container, "pg_dump", "-U", "supabase_admin", "-d", "postgres", "--schema-only", "--exclude-schema=public"]));
sql("alter default privileges for role postgres in schema public revoke select,insert,update,delete on tables from anon,authenticated,service_role; alter default privileges for role postgres in schema public revoke select,usage on sequences from anon,authenticated,service_role; alter default privileges for role postgres in schema public revoke execute on functions from public,anon,authenticated,service_role;");
const migrations = readdirSync(resolve(root, "supabase/migrations")).filter((name) => name.endsWith(".sql")).sort();
for (const migration of migrations) file(`supabase/migrations/${migration}`);
file("supabase/seed.sql");
assert.equal(migrations.at(-1), "20260921000300_e1_t16_flujo_actual_pedidos.sql");
console.log(`PASS replay limpio: ${migrations.length} migraciones + seed`);
console.log(file("supabase/tests/e1_t16_flujo_actual_pedidos.sql"));
for (const regression of ["h4_t04_derived_order_table_state", "e1_t12_reportes_caja"]) {
  console.log(file(`supabase/tests/${regression}.sql`));
  console.log(`PASS regresión afectada: ${regression}`);
}
console.log(`DATABASE=${database}`);

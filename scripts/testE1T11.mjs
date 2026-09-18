import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";

const root = fileURLToPath(new URL("../", import.meta.url));
const container = process.argv[2];
const baseline = process.argv[3];
assert.match(container ?? "", /^mikuyapp-e1-t(?:09|11)-validation-[a-z0-9-]+$/);
assert.match(baseline ?? "", /^e1_t(?:09|10)_[a-z0-9_]+$/);

function docker(args, input) {
  const result = spawnSync("docker", args, {
    input,
    encoding: "utf8",
    timeout: 120_000,
    maxBuffer: 32e6,
  });
  if (result.error || result.status !== 0)
    throw new Error(result.error?.message ?? result.stderr);
  return result.stdout.trim();
}

const [metadata] = JSON.parse(docker(["inspect", container]));
assert.equal(metadata.HostConfig.NetworkMode, "none");
assert.equal(metadata.Mounts.some((item) => item.Type === "bind"), false);

const database = `e1_t11_${randomUUID().replaceAll("-", "")}`;
docker([
  "exec",
  container,
  "createdb",
  "-U",
  "postgres",
  `--template=${baseline}`,
  database,
]);
const psql = [
  "exec",
  "-i",
  container,
  "psql",
  "-XqAt",
  "-U",
  "postgres",
  "-d",
  database,
  "-v",
  "ON_ERROR_STOP=1",
  "-v",
  "VERBOSITY=verbose",
];
const sqlFile = (path) =>
  docker(psql, readFileSync(resolve(root, path), "utf8"));

sqlFile("supabase/migrations/20260917000100_e1_t11_auditoria_financiera.sql");
console.log(sqlFile("supabase/tests/e1_t11_auditoria_financiera.sql"));
for (const name of [
  "e1_t04_apertura_sesion",
  "e1_t05_movimientos_cierre",
  "e1_t06_descuento_pedido",
  "e1_t07_anulacion_administrativa",
  "e1_t09_pagos_multiples",
]) {
  sqlFile(`supabase/tests/${name}.sql`);
  console.log(`PASS regresión de auditoría: ${name}`);
}
console.log(`PASS T11 incremental en ${container}/${database}`);

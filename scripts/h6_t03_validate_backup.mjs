import { createHash } from 'node:crypto'
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { createClient } from '@supabase/supabase-js'
import { csv } from '../src/services/salesService.ts'

const [administrativeDirectory, secondaryDirectory] = process.argv.slice(2)
const required = ['VITE_SUPABASE_URL', 'VITE_SUPABASE_PUBLISHABLE_KEY', 'H2_ADMIN_EMAIL', 'H2_ADMIN_PASSWORD']
const missing = required.filter((name) => !process.env[name]?.trim())
if (!administrativeDirectory || !secondaryDirectory || missing.length) {
  throw new Error(`Uso: h6_t03_validate_backup.mjs <copia-administrativa> <segunda-copia>. Faltan: ${missing.join(', ')}`)
}

const client = createClient(process.env.VITE_SUPABASE_URL, process.env.VITE_SUPABASE_PUBLISHABLE_KEY, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } })
const login = await client.auth.signInWithPassword({ email: process.env.H2_ADMIN_EMAIL, password: process.env.H2_ADMIN_PASSWORD })
if (login.error || !login.data.session) throw new Error('No se pudo autenticar al administrador para validar el respaldo.')

const exports = [
  ['ventas', 'exportar_ventas_hoy'],
  ['productos', 'exportar_productos_local'],
]
const stamp = new Date().toISOString().slice(0, 10)
await mkdir(administrativeDirectory, { recursive: true })
await mkdir(secondaryDirectory, { recursive: true })
const evidence = []

for (const [kind, rpc] of exports) {
  const result = await client.rpc(rpc)
  if (result.error) throw new Error(`Falló ${rpc}: ${result.error.message}`)
  if (!Array.isArray(result.data) || result.data.length === 0) throw new Error(`${rpc} no devolvió filas para la validación controlada.`)
  const content = `\uFEFF${csv(result.data)}`
  const name = `mikuyapp-${kind}-${stamp}.csv`
  const primaryPath = join(administrativeDirectory, name)
  const secondaryPath = join(secondaryDirectory, name)
  await writeFile(primaryPath, content, 'utf8')
  await writeFile(secondaryPath, content, 'utf8')
  const [primary, secondary] = await Promise.all([readFile(primaryPath), readFile(secondaryPath)])
  const hash = (buffer) => createHash('sha256').update(buffer).digest('hex')
  if (!primary.length || primary.length !== secondary.length || hash(primary) !== hash(secondary)) throw new Error(`Las copias de ${name} no coinciden.`)
  evidence.push({ archivo: name, filas: result.data.length, bytes: primary.length, sha256: hash(primary), copiasCoinciden: true })
}

await client.auth.signOut()
console.log(JSON.stringify({ resultado: 'H6-TP08 OK', archivos: evidence }, null, 2))

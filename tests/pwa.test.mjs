import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const root = dirname(dirname(fileURLToPath(import.meta.url)))
const read = (path) => readFile(join(root, path), 'utf8')

test('H6-TP13: manifest define identidad, instalación standalone e iconos requeridos', async () => {
  const manifest = JSON.parse(await read('public/manifest.webmanifest'))
  assert.equal(manifest.name, 'MikuyApp')
  assert.equal(manifest.short_name, 'MikuyApp')
  assert.equal(manifest.start_url, '/')
  assert.equal(manifest.scope, '/')
  assert.equal(manifest.display, 'standalone')
  assert.deepEqual(manifest.icons.map(({ sizes }) => sizes), ['192x192', '512x512'])
})

test('H6-TP13: HTML enlaza manifest, identidad y metadatos de instalación', async () => {
  const html = await read('index.html')
  assert.match(html, /rel="manifest" href="\/manifest\.webmanifest"/)
  assert.match(html, /rel="apple-touch-icon" href="\/apple-touch-icon\.png"/)
  assert.match(html, /name="theme-color" content="#065f46"/)
  assert.match(html, /<title>MikuyApp<\/title>/)
})

test('H6-TP13: service worker habilita instalación sin caché ni lógica offline', async () => {
  const [main, worker] = await Promise.all([read('src/main.tsx'), read('public/service-worker.js')])
  assert.match(main, /serviceWorker\.register\('\/service-worker\.js'\)/)
  assert.doesNotMatch(worker, /fetch|caches|CacheStorage/)
})

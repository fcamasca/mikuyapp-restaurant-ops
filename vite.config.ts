import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  // TEMPORAL — E7-T12/TH06: identifica el commit desplegado en el panel de diagnóstico Realtime.
  define: { __MIKUY_BUILD__: JSON.stringify(process.env.CF_PAGES_COMMIT_SHA ?? 'local') },
})

import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { defineConfig } from 'vite'
import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const frontendRoot = fileURLToPath(new URL('.', import.meta.url))

export default defineConfig({
  root: frontendRoot,
  plugins: [react(), tailwindcss()],
  publicDir: resolve(frontendRoot, 'public'),
  build: {
    rollupOptions: {
      input: [
        resolve(frontendRoot, 'index.html'),
        resolve(frontendRoot, 'prototypes/cocinapp.html'),
      ],
    },
  },
})

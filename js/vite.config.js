// vite.config.js
import { resolve } from 'path'
import { defineConfig } from 'vite'
import dts from 'vite-plugin-dts'

export default defineConfig(({ mode }) => ({
  plugins: [
    dts({ insertTypesEntry: true }),
  ],
  build: {
    minify: false,
    lib: {
      entry: {
        alternis: resolve(__dirname, 'src/index.ts'),
        "alternis-worker": resolve(__dirname, 'src/worker-api.ts'),
      },
      name: 'Alternis',
    },
    rollupOptions: {
    },
  },
}))

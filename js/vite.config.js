// vite.config.js
import { resolve } from 'path'
import { defineConfig } from 'vite'
import dts from 'vite-plugin-dts'

export default defineConfig(({ mode }) => ({
  plugins: [
    dts({ insertTypesEntry: true }),
  ],
  build: {
    minify: mode === "production",
    lib: {
      entry: resolve(__dirname, 'src/index.ts'),
      name: 'Alternis',
      fileName: 'alternis',
    },
    rollupOptions: {
    },
  },
}))

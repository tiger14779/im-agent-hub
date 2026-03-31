import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import basicSsl from '@vitejs/plugin-basic-ssl'
import { resolve } from 'path'

const useHttps = process.env.VITE_HTTPS === 'true'

export default defineConfig({
  plugins: [vue(), ...(useHttps ? [basicSsl()] : [])],
  resolve: {
    alias: {
      '@': resolve(__dirname, 'src')
    }
  },
  server: {
    port: 3000,
    proxy: {
      '/api': {
        target: 'http://localhost:8080',
        changeOrigin: true,
        ws: true
      }
    }
  },
  build: {
    outDir: 'dist'
  },
  optimizeDeps: {
    exclude: ['@openim/wasm-client-sdk']
  },
  assetsInclude: ['**/*.wasm']
})

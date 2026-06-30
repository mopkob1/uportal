import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

const backendTarget = (process.env.UPORTAL_DEV_SERVER_URL || process.env.VITE_UPORTAL_DEFAULT_SERVER_URL || 'http://127.0.0.1:8080').replace(/\/+$/, '')

export default defineConfig({
  plugins: [vue()],
  server: {
    host: '0.0.0.0',
    port: 5173,
    proxy: {
      '/api': {
        target: backendTarget,
        changeOrigin: true,
        secure: !backendTarget.startsWith('http://127.0.0.1') && !backendTarget.startsWith('http://localhost')
      },
      '/upload': {
        target: backendTarget,
        changeOrigin: true,
        secure: !backendTarget.startsWith('http://127.0.0.1') && !backendTarget.startsWith('http://localhost')
      }
    }
  }
})

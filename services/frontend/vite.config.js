import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react-swc'

// https://vitejs.dev/config/
export default defineConfig({
    plugins: [react()],
    server: {
        host: true,
        port: 5173,
        proxy: {
            '/api': {
                target: 'http://localhost:8081',
                changeOrigin: true,
            },
            '/realms': {
                target: 'http://k8s-zerotrus-keycloak-6984eeed45-1666704128.us-east-1.elb.amazonaws.com',
                changeOrigin: true,
            }
        }
    }
})

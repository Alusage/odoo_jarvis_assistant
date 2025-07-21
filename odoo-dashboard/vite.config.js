import { defineConfig } from 'vite'
import { resolve } from 'path'
import { readFileSync } from 'fs'
import { join } from 'path'

// Fonction pour lire la configuration Traefik de manière dynamique
function getTraefikConfig() {
  // Priorité à la variable d'environnement
  if (process.env.TRAEFIK_DOMAIN) {
    return process.env.TRAEFIK_DOMAIN
  }
  
  try {
    const configPath = join(process.cwd(), 'config/traefik_config.json')
    const configContent = readFileSync(configPath, 'utf-8')
    const config = JSON.parse(configContent)
    return config.domain || 'localhost'
  } catch (error) {
    console.warn('Could not read Traefik config, using localhost:', error.message)
    return 'localhost'
  }
}

// Générer dynamiquement la liste des hosts autorisés
function generateAllowedHosts() {
  const domain = getTraefikConfig()
  console.log(`🌐 Vite: Using domain "${domain}" from Traefik config`)
  
  return [
    'localhost',
    '127.0.0.1',
    `dashboard.${domain}`,
    `dashboard.localhost`,
    // Patterns génériques pour supporter différents domaines
    `.${domain}`,
    '.localhost',
    '.local',
    '.dev',
    // Domaines spécifiques courants
    'dashboard.local',
    'dashboard.dev'
  ]
}

export default defineConfig({
  root: '.',
  base: './',
  server: {
    port: 3000,
    open: true,
    host: '0.0.0.0',
    allowedHosts: generateAllowedHosts()
  },
  build: {
    outDir: 'dist',
    assetsDir: 'assets',
    rollupOptions: {
      input: {
        main: resolve(__dirname, 'index.html')
      }
    }
  },
  resolve: {
    alias: {
      '@': resolve(__dirname, 'src'),
      '@components': resolve(__dirname, 'src/components'),
      '@services': resolve(__dirname, 'src/services'),
      '@assets': resolve(__dirname, 'src/assets'),
      '@styles': resolve(__dirname, 'src/styles')
    }
  },
  optimizeDeps: {
    include: ['@odoo/owl']
  }
})
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  define: {
    // Data di build: è ciò che serve davvero all'assistenza per capire quale
    // versione del sito ha in mano chi scrive. Mostrata in Impostazioni.
    __BUILD_DATE__: JSON.stringify(new Date().toISOString().slice(0, 10)),
  },
})

import { mount } from 'svelte'
import './lib/theme/theme.css'
import App from './App.svelte'
import { registerServiceWorker } from './lib/push/push-manager'
import { migrateFromLocalStorage, purgeOldData } from './lib/db'

const app = mount(App, {
  target: document.getElementById('app')!,
})

// Register service worker on load (doesn't request notification permission — that needs user gesture)
if (import.meta.env.PROD) {
  registerServiceWorker()
}

// Migrate localStorage data to IndexedDB, then purge stale entries
migrateFromLocalStorage()
  .then(() => purgeOldData())
  .catch((e) => console.warn('[MajorTom] DB init failed:', e))

export default app

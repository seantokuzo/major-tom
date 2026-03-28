import { mount } from 'svelte'
import './lib/theme/theme.css'
import { registerServiceWorker } from './lib/push/push-manager'
import { migrateFromLocalStorage, purgeOldData } from './lib/db'

// Run DB migration/purge BEFORE mounting the app so stores don't read an empty DB
async function bootstrap() {
  try {
    await migrateFromLocalStorage()
    await purgeOldData()
  } catch (e) {
    console.warn('[MajorTom] DB init failed:', e)
  }

  const { default: App } = await import('./App.svelte')
  const app = mount(App, {
    target: document.getElementById('app')!,
  })

  // Register service worker on load (doesn't request notification permission — that needs user gesture)
  if (import.meta.env.PROD) {
    registerServiceWorker()
  }

  return app
}

export default bootstrap()

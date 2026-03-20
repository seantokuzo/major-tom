import { mount } from 'svelte'
import './lib/theme/theme.css'
import App from './App.svelte'
import { registerServiceWorker } from './lib/push/push-manager'

const app = mount(App, {
  target: document.getElementById('app')!,
})

// Register service worker on load (doesn't request notification permission — that needs user gesture)
if (import.meta.env.PROD) {
  registerServiceWorker()
}

export default app

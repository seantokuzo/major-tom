// Major Tom — Service Worker
// Handles push notifications and notification click routing

self.addEventListener('push', (event) => {
  const fallback = { type: 'approval', title: 'Major Tom', body: 'Major Tom needs your attention', data: {} };
  let data = fallback;

  if (event.data) {
    try {
      const parsed = event.data.json();
      data = {
        type: parsed.type || fallback.type,
        title: typeof parsed.title === 'string' ? parsed.title : fallback.title,
        body: typeof parsed.body === 'string' ? parsed.body : fallback.body,
        data: parsed.data && typeof parsed.data === 'object' ? parsed.data : fallback.data,
      };
    } catch {
      // JSON parse failed — try plain text, fall back to default
      try {
        const text = event.data.text();
        if (text) data = { ...fallback, body: text };
      } catch {
        // Use fallback as-is
      }
    }
  }

  const options = {
    body: data.body,
    icon: '/favicon.svg',
    badge: '/favicon.svg',
    tag: 'major-tom-approval',
    renotify: true,
    requireInteraction: true,
    data: data.data || {},
  };

  event.waitUntil(self.registration.showNotification(data.title || 'Major Tom', options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const rawUrl = event.notification.data?.url;
  let url = typeof rawUrl === 'string' ? rawUrl : '/';

  // Restrict to same-origin URLs for security
  if (url.startsWith('/')) {
    // Relative path — safe
  } else {
    try {
      if (new URL(url).origin !== self.location.origin) {
        url = '/';
      }
    } catch {
      url = '/';
    }
  }

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windowClients) => {
      // Try to focus an existing window
      for (const client of windowClients) {
        if (new URL(client.url).origin === self.location.origin) {
          if (url !== '/') {
            return client.focus().then(() => client.navigate(url));
          }
          return client.focus();
        }
      }
      // No existing window — open a new one
      return clients.openWindow(url);
    })
  );
});

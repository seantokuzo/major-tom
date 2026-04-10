// Major Tom — Service Worker
// Handles push notifications and notification click routing.
//
// Phase 13 Wave 2 added:
//   - per-request tag (`data.tag`) so the SW can dedup notifications
//     across devices: when one device resolves an approval, the relay
//     re-pushes a `mt-approval-resolved` payload that we use to close
//     any matching showing notification.
//   - inline action buttons that POST the decision to /api/approvals
//     directly from the SW context, so the user can answer without
//     ever opening the PWA.
//   - postMessage broadcast to all visible clients on click, so the
//     ApprovalOverlay can re-fetch the live queue and stay in sync.

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

  // ── Cross-device dismissal ─────────────────────────────────
  // The relay's notification-batcher tags single approvals with their
  // requestId so we can resolve+dismiss in lockstep. A `dismiss`-typed
  // payload tells us to close any existing notification with that tag
  // without opening a new one.
  const tag = (data.data && typeof data.data.tag === 'string') ? data.data.tag : 'major-tom-approval';
  if (data.type === 'approval.dismiss' || data.type === 'mt-approval-resolved') {
    event.waitUntil(
      self.registration.getNotifications({ tag }).then((existing) => {
        for (const n of existing) n.close();
        // Also tell live clients so the overlay can drop the card.
        return self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((winClients) => {
          for (const c of winClients) {
            c.postMessage({ type: 'mt-approval-resolved', requestId: data.data?.requestId });
          }
        });
      })
    );
    return;
  }

  // ── "Done working" notification ─────────────────────────────
  // Simple informational notification — no action buttons, auto-dismisses.
  if (data.type === 'done') {
    const opts = {
      body: data.body,
      icon: '/favicon.svg',
      badge: '/favicon.svg',
      tag: 'mt-done',
      renotify: true,
      requireInteraction: false,
      data: data.data || {},
    };
    event.waitUntil(self.registration.showNotification(data.title || 'Major Tom', opts));
    return;
  }

  // ── Action buttons ─────────────────────────────────────────
  // Only attach Allow/Deny actions when the payload carries a real
  // requestId — batched payloads don't, so they'd point at nothing.
  const requestId = (data.data && typeof data.data.requestId === 'string') ? data.data.requestId : null;
  const actions = requestId
    ? [
        { action: 'mt-allow', title: 'Allow' },
        { action: 'mt-deny', title: 'Deny' },
      ]
    : [];

  const options = {
    body: data.body,
    icon: '/favicon.svg',
    badge: '/favicon.svg',
    tag,
    renotify: true,
    requireInteraction: true,
    data: data.data || {},
    actions,
  };

  event.waitUntil(self.registration.showNotification(data.title || 'Major Tom', options));
});

self.addEventListener('notificationclick', (event) => {
  const requestId = event.notification.data?.requestId;
  const action = event.action;

  // ── Inline allow/deny ─────────────────────────────────────
  // The user tapped a notification action button. POST the decision
  // straight to the relay so the shell hook unblocks even if no PWA
  // tab is open. Then close the notification and broadcast to any
  // open clients so they can drop the card.
  if (requestId && (action === 'mt-allow' || action === 'mt-deny')) {
    const decision = action === 'mt-allow' ? 'allow' : 'deny';
    event.notification.close();
    event.waitUntil(
      (async () => {
        // Mirror the relay.svelte.ts respondToApprovalRest contract:
        //   - 2xx → success
        //   - 404 → already resolved by another device, treat as success
        //   - any other status → failure, surface an error notification
        //     and DO NOT broadcast mt-approval-resolved (otherwise live
        //     PWAs would drop the card even though nothing was decided)
        let res;
        let networkFailed = false;
        try {
          res = await fetch(`/api/approvals/${encodeURIComponent(requestId)}/decision`, {
            method: 'POST',
            credentials: 'include',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ decision }),
          });
        } catch {
          networkFailed = true;
        }

        const succeeded = !networkFailed && res && (res.ok || res.status === 404);

        if (!succeeded) {
          // Network or server error — surface a follow-up notification
          // so the user knows their decision didn't land. Tagged
          // differently so it doesn't replace anything important.
          const reason = networkFailed
            ? 'network error'
            : `server returned ${res?.status ?? 'unknown'}`;
          await self.registration.showNotification('Major Tom', {
            body: `Couldn't send decision (${decision}) — ${reason}. Open the app to retry.`,
            tag: 'mt-approval-error',
            icon: '/favicon.svg',
          });
          return;
        }

        // Only broadcast resolution to live clients on success.
        const winClients = await self.clients.matchAll({
          type: 'window',
          includeUncontrolled: true,
        });
        for (const c of winClients) {
          c.postMessage({ type: 'mt-approval-resolved', requestId });
        }
      })()
    );
    return;
  }

  // ── Notification body click (no action) ───────────────────
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
      // Tell every open client we just navigated for an approval — they
      // re-fetch the pending queue so the overlay shows the freshest
      // state without waiting for a WS round-trip.
      for (const c of windowClients) {
        c.postMessage({ type: 'mt-approval-nav', requestId });
      }
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

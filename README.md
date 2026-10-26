# Bato

Separate from Piesa. A bilingual, mobile-first, installable web app prototype connecting US-to-West-Africa cargo senders and shippers.

## Development

Use Node.js 22+:

```sh
npm ci
npm run dev
```

Production:

```sh
npm run build
npm run preview
```

Deploy the complete `dist/` directory to an HTTPS static host. Keep `/manifest.webmanifest`, icons and `/sw.js` accessible. Host at the domain root with SPA fallback to `/index.html`. Do not cache `sw.js` indefinitely. No deployment has been performed.

## Save to a phone

Open the deployed HTTPS site. Android Chrome: select **Install app** in the app or browser menu. iPhone Safari: **Share → Add to Home Screen → Add**. Launch using the home-screen icon. Includes standalone display, regular and maskable icons, Apple touch icon, service-worker precaching, offline status, and an update prompt. Localhost is supported for development; a plain HTTP LAN address is not installable. Browser testing validates offline reload, but physical iPhone/Android installation remains untested.

## Prototype features

- EN/FR UI, city/destination/date filters, sample departures.
- Local cargo requests and shipper departure posting, local inquiry/offer drafts.
- Explicit arrival-port selection and pickup acknowledgment for Bamako/Niamey; inland transport excluded.
- Georgia-to-Lomé car quote drafts with vehicle details and optional photos.
- Shipper membership interest form. Senders free. No freight payments collected by app.

## Limitations

All submissions are stored only in this browser's localStorage. Nothing is sent to other users; inquiries are not bookings. Sample operators, space and dates are fictional. Demo dates are generated relative to the device date, including offline. The Georgia express operator contact and transit estimate are not supplied. No authentication, backend, membership payment processor, notifications, moderation, or real-time shared inventory exists. Prices and membership amounts have not been set. Demo departure posting does not enforce paid membership. Offline mode shows cached UI and local data; it does not synchronize. Photos are limited to four images at 1 MB each; browser storage capacity can still be exceeded, in which case the form reports an error. Personal data and photos stay on the device; use only test data in this prototype.

Before launch: implement authentication/roles, shared database, server-side validation, shipper verification, membership billing and webhooks, messaging, deployment, privacy controls, data retention, actual express-service details, and real-device install tests.

## Validation

Production build passed. Chromium browser checks passed for initial catalog, EN/FR switching, cargo posting, inland-port acknowledgment, express car inquiries, installation guidance, mobile overflow, service-worker activation, and offline reload. No uncaught page errors occurred. Physical phone installation and live multi-user operations remain untested.

## Bato branding

Updated from the supplied **Bato Logo.pdf**. Exact palette: Ocean `#0E2A47`, Container `#E8743B`, Route `#F2B134`, Sand `#F7F4EE`. The supplied logo artwork is extracted directly into `public/bato-logo.png`; phone icons and Apple touch icon are extracted from the supplied app icon artwork. The PDF embeds raster artwork, so these are PNG assets rather than vector logo masters. The original guide is retained at `public/bato-brand-guide.pdf`. The original Sora wordmark is preserved in the extracted artwork. The app name, page title, manifest, theme color, UI surfaces, and install icons now use Bato. The source directory remains `/workspace/diaspocargo`; browser storage keys stay unchanged to preserve existing local records.

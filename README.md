# Connect Bato accounts and administration

1. Create a new Supabase project. In **SQL Editor**, run `schema.sql` once. It creates profiles, memberships, moderated listings, audit records, signup trigger, RLS policies and protected admin RPCs. This script is for a fresh project; do not rerun it on a populated database.
2. In **Authentication → URL Configuration**, set Site URL to your production HTTPS address. Add the exact production address and `http://localhost:5173` as allowed redirect URLs. Add preview URLs only when needed.
3. Enable email/password authentication and email confirmation. Configure production SMTP and authentication rate limits before a public launch. The built-in development mail service is not suitable for large-scale delivery.
4. In Vercel, add `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` from your project's public API settings. An older public anon key also works as `VITE_SUPABASE_ANON_KEY`. These values are compiled into the browser bundle. **Never use the service_role/secret key.** Redeploy after adding or changing them.
5. Create your own account through Bato and confirm the email. From the trusted Supabase SQL editor, promote only your own known user UUID:

```sql
-- Find your account's UUID in Authentication → Users, then replace this value.
update public.profiles set role = 'admin'
where id = 'YOUR-USER-UUID';
```

6. Sign out and back in. Open **My account → Admin dashboard**. Regular accounts do not receive this access. Admin functions recheck permissions in PostgreSQL regardless of what the browser displays.

## Roles

- Sender: free account, create cargo requests, view listings, save local inquiries.
- Shipper: account signup allowed; active membership required to submit departures and cargo offers. Memberships currently use manually granted pilot access, not automated billing.
- Admin: review/approve/hide listings, change roles or suspend other accounts, set manual shipper membership expirations, and view audit events. Self-demotion/suspension is blocked through the admin UI/RPC to avoid accidental lockout. First admin promotion requires the trusted SQL editor; no public signup option or browser secret exists.

## Data behavior

Connected mode displays only approved live listings, plus the signed-in user's listings in My account. New listings enter `pending`. Admins approve them. Personal emails are stored in private profiles, never public listing payloads. Profile and membership writes are not granted to browser roles. Listing ownership, moderation state and membership eligibility are enforced by RLS; payload validation runs in a database trigger. Suspending an owner removes their approved listings from public queries. Membership expiration blocks new shipper submissions; it does not remove previously approved departures.

Unconfigured mode offers sample listings and a clear setup notice instead of accepting login credentials. Existing browser-local sample data is not imported to Supabase. Inquiries/express quotes/photos remain drafts on the current device, scoped to the signed-in account, and are not shared with shippers or admins. Messaging and payment processing are not implemented in this change. Public listing reads require network access; the cached app still opens offline and reports loading failures.

## Before launch

Verify on your actual project with two users and one admin: email confirmation, password reset, sender and shipper sign-in, rejection of sender departure inserts, rejection of unentitled shipper departure inserts, inability to set admin role via signup metadata or direct profile writes, inability to approve your own listing, pending/approved/hidden visibility, suspension enforcement, and private email isolation. These live checks require your Supabase project and have not been performed against a hosted project here.

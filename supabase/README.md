# Supabase migration runbook

Project URL: `https://jxttqxupjeteihjkdcvg.supabase.co`

Firebase remains the rollback system until the mobile app and web dashboard pass the Supabase verification tests. Do not delete Firebase data during migration.

## 1. Install tools

Install these locally:

- Supabase CLI
- Git
- Flutter SDK
- Node.js LTS, if using Vercel CLI or JavaScript tooling

Then authenticate:

```bash
supabase login
supabase link --project-ref jxttqxupjeteihjkdcvg
```

## 2. Apply the database schema

The prepared migration is:

```text
supabase/migrations/202609200001_initial_schema.sql
```

Apply it:

```bash
supabase db push
```

In Supabase Dashboard, verify under **Table Editor** that these tables exist:

`profiles`, `properties`, `rooms`, `tenants`, `payments`, `sms_queue`, `audit_logs`

## 3. Configure authentication

In Supabase Dashboard:

1. Open **Authentication > Providers**.
2. Enable Email provider.
3. Configure the email confirmation and password reset URLs.
4. Add your Vercel production URL to **Authentication > URL Configuration**.
5. Add the Vercel preview URL if preview testing is required.

Create the first superadmin account through Supabase Auth. Then update its profile in the SQL editor:

```sql
update public.profiles
set role = 'superadmin', permissions = array['platform']
where email = 'YOUR_SUPERADMIN_EMAIL';
```

Never create a superadmin role from untrusted browser input.

## 4. Configure UniSMS

Revoke the old exposed UniSMS key and create a replacement key. Store it only as a Supabase secret:

```bash
supabase secrets set UNISMS_API_KEY=YOUR_NEW_UNISMS_KEY
```

Deploy the prepared Edge Function:

```bash
supabase functions deploy send-sms
```

The function is located at:

```text
supabase/functions/send-sms/index.ts
```

It validates the Supabase access token, checks `owner` or `superadmin` access, normalizes Philippine numbers, and calls UniSMS without exposing the key to Flutter or the browser.

## 5. Prepare Vercel

In Vercel, choose **Add New > Project**, import this repository, and use:

- Framework preset: `Other`
- Root directory: repository root
- Build command: empty
- Output directory: `build/web`
- Install command: empty

Add these variables to **Production**, **Preview**, and **Development**:

```text
SUPABASE_URL=https://jxttqxupjeteihjkdcvg.supabase.co
SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_PUBLIC_KEY
```

The anon key is allowed in client applications because RLS protects the tables. Never add `service_role` to Vercel client variables or commit it.

Deploy from the Vercel dashboard or CLI:

```bash
vercel --prod
```

Verify these URLs load:

```text
https://YOUR_VERCEL_DOMAIN/index.html
https://YOUR_VERCEL_DOMAIN/admin.css
https://YOUR_VERCEL_DOMAIN/admin.js
```

## 6. Migrate data

Export Firebase collections before changing clients:

`users`, `owners`, `rooms`, `tenants`, `payments`, `sms_queue`, and `audit_logs`

Map the data as follows:

| Firebase | Supabase |
|---|---|
| `users` / `admins` | `profiles` |
| `owners` | `profiles` with role `owner` |
| `rooms` | `rooms` |
| `tenants` | `tenants` |
| `payments` | `payments` |
| `sms_queue` | `sms_queue` |
| `audit_logs` | `audit_logs` |

Keep the original Firebase document IDs in a temporary mapping if the IDs are not valid UUIDs. The prepared Supabase schema uses UUID primary keys.

## 7. Client migration status

The web dashboard now uses Supabase Auth, PostgreSQL tables, RLS, and the `send-sms` Edge Function. Vercel provides the public Supabase configuration through `/api/config`.

The Flutter app remains on Firebase while its authentication and offline sync are migrated separately:

1. Migrate Flutter authentication to Supabase Auth.
2. Replace Flutter Firestore sync with Supabase PostgreSQL queries and realtime streams.
3. Verify owner isolation with two owner accounts.
4. Run Firebase and Supabase in comparison mode.
5. Remove Firebase dependencies only after all tests pass.

## 8. Required acceptance tests

- Owner A cannot read or update Owner B's rooms, tenants, payments, or SMS records.
- Superadmin can view all properties and financial records.
- Disabled profiles cannot access protected data.
- A tenant confirmation SMS is sent through the `send-sms` Edge Function.
- A monthly reminder creates one queue record per tenant and does not duplicate it.
- Payment totals match the Firebase export.
- Dashboard refresh works on the Vercel domain.
- Password reset works using the Vercel redirect URL.

Do not retire Firebase until every acceptance test passes and a final backup has been verified.

# DOS Akademie Portal

بوابة أكاديمية **Drei Online Spezialisten** لإدارة الطلاب والمحاضرين والموظفين، مع مكتبة رقمية وورقية، جلسات مذاكرة، تقارير مالية، ومواد تعليم اللغة الألمانية.

## Features

- Student, instructor, employee, and administrator portals.
- Student study sessions with German voice notifications, 20-minute breaks, live status, and CSV reports.
- Separate digital and paper libraries.
- In-page digital library viewer and permission-controlled paper downloads.
- Student requests, attendance, payments, invoices, receipts, and employee work sessions.
- Supabase Realtime updates for study sessions and portal data.
- German course pages for A1, A2, and B1 materials.

## Project Structure

- `../index.html`: Main portal and React application.
- `../HTML/`: Course content pages and invoice/receipt templates.
- `./manifest.webmanifest` and `./DOS Logo.png`: PWA manifest and app logo.
- `../service-worker.js`: Root-scoped service worker.
- `supabase/`: Supabase Edge Functions.
- `*.sql`: Database migrations and Row Level Security policies.

## Local Use

The portal is a static HTML application and can be served with any static web server. From the repository root, for example:

```powershell
python -m http.server 8080
```

Then open:

```text
http://localhost:8080/
```

Opening the file directly may work for the basic UI, but a local web server is recommended for Supabase requests, iframe content, and browser security rules.

## Supabase Setup

1. Create or use a Supabase project.
2. Confirm the values at the top of `index.html`:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
3. Run the required SQL migrations in the Supabase SQL Editor. For the full portal, run them in this order:

```text
attendance_records.sql
supabase_requests_migration.sql
supabase_digital_library_migration.sql
supabase_student_library_study_migration.sql
supabase_employee_permissions_migration.sql
supabase_instructors_migration.sql
   supabase_landing_applications_migration.sql
```

Run only the migrations that match the tables already present in your database. Review the policies before using the application in production.

## Edge Function: manage-users

The administrator portal creates, deletes, and resets users through the `manage-users` Edge Function.

Source file:

```text
supabase/functions/manage-users/index.ts
```

Deploy it with the Supabase CLI:

```powershell
npx supabase login
npx supabase functions deploy manage-users --project-ref YOUR_PROJECT_REF
```

The function requires Supabase's standard environment variables. `SUPABASE_SERVICE_ROLE_KEY` must remain server-side and must never be placed in `index.html`.

## Protect digital library files

Deploy the authenticated content stream, then run `Supabase File/supabase_library_content_protection_migration.sql` in the Supabase SQL Editor. The migration makes the `course-library` bucket private, removes direct file-read policies, and preserves paper downloads only when permitted.

```powershell
npx supabase functions deploy library-content --no-verify-jwt --project-ref YOUR_PROJECT_REF
```

The function validates the user's Supabase session and library permission itself. The service-role key stays in Supabase and is never sent to the browser. Previously issued signed links may remain usable until their one-hour expiry; newly refreshed library entries no longer receive signed links.

## Landing application email

Run `supabase_landing_applications_migration.sql` before using the public reservation form. The form stores one application per normalized email, shows the request only to authorized portal users, and sends a confirmation email through:

```text
supabase/functions/send-landing-application-email/index.ts
```

Deploy the function and configure its server-side secrets:

```powershell
npx supabase functions deploy send-landing-application-email --project-ref YOUR_PROJECT_REF
npx supabase secrets set RESEND_API_KEY=YOUR_RESEND_KEY DOS_FROM_EMAIL="DOS Academy <info@dos-eg.com>" DOS_APP_URL="https://dos-info-eg.github.io/Drei-Online-Spezialisten/"
```

The browser uses Supabase over HTTPS, so it can work with or without a VPN when the Supabase project and the visitor's network are reachable. A web page cannot create or control a VPN connection itself.

## Landing reservation email

Deploy `supabase/functions/send-landing-application-email/index.ts` and configure the Edge Function secrets `RESEND_API_KEY`, `DOS_FROM_EMAIL`, and `DOS_APP_URL`. The public form stores one reservation per email and sends the applicant a confirmation summary through Resend.

## GitHub Pages

The repository can be published as a static GitHub Pages site. Keep the root `index.html`, `HTML/`, `Foto/`, and `service-worker.js` in the published directory. The Open Graph metadata points to the logo in `Foto/`:

```text
https://dos-info-eg.github.io/Drei-Online-Spezialisten/
```

After publishing, social platforms may cache the previous preview image. Re-scrape the URL using the platform's link debugger when necessary.

## Install as a phone app (PWA)

The portal includes PWA support through `Foto/manifest.webmanifest`, `service-worker.js`, and `Foto/DOS Logo.png`.

1. Publish the complete `DOS Web` folder on GitHub Pages or another host with HTTPS.
2. Open the published site URL in Chrome on Android, then choose **Install DOS Web** or **Add to Home screen**.
3. On iPhone, open the URL in Safari, tap **Share**, then choose **Add to Home Screen**.

The app shell is cached after the first visit, so the interface can open without a connection. Login, Supabase data, realtime updates, and remote CDN libraries still require internet access.

## Security Notes

- Keep Row Level Security enabled for all Supabase tables and storage objects.
- Use signed URLs for private library files.
- The Supabase anon key may be visible in a browser application, but database access must be protected by RLS policies.
- Never commit service-role keys, database passwords, or Supabase access tokens.
- Digital content can be displayed inside the site, but no browser application can fully prevent screenshots or developer tools.

## License

No license has been specified for this repository yet.

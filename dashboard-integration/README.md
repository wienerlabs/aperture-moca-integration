# Dashboard integration (Faz 1)

These files are the AIR Account login integration for Aperture's existing
Next.js dashboard. They are patches against the main Aperture dashboard and are
not runnable standalone (they import from the dashboard's `@/lib` paths and use
its NextAuth setup). They are included here for completeness.

- `auth.ts` - adds an additive `air` NextAuth CredentialsProvider that validates
  the AIR token claims (partner id, expiry, bound abstract account).
- `signin-page.tsx` - adds a "Sign in with AIR Account (Moca)" button next to the
  existing wallet login.
- `airkit-login.ts` - loads the AIR Kit SDK from an ESM CDN at click time and
  runs `login()`, returning the token + abstract account address.

In the main dashboard these live at `src/lib/auth.ts`,
`src/app/auth/signin/page.tsx` and `src/lib/airkit-login.ts` respectively.

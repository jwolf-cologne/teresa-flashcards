# `flashcards-ai`

Supabase Edge Function for the Flashcards iOS app.

## Secrets

Set the OpenAI key in Supabase, not in the app:

```bash
npx supabase@latest secrets set OPENAI_API_KEY="sk-..." --project-ref <project-ref>
```

Optional model override:

```bash
npx supabase@latest secrets set OPENAI_MODEL="gpt-5-mini" --project-ref <project-ref>
```

KI calls are protected by an App Store auto-renewable subscription. Create an
App Store Connect subscription product with the same product identifier used in
the app:

```text
flashcards_ai_monthly
```

Then create an App Store Connect API key with access to the App Store Server
API and store these secrets in Supabase:

```bash
npx supabase@latest secrets set \
  APP_STORE_ISSUER_ID="<issuer-id>" \
  APP_STORE_KEY_ID="<key-id>" \
  APP_STORE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----" \
  APP_STORE_BUNDLE_ID="wolf.Flashcards" \
  AI_SUBSCRIPTION_PRODUCT_ID="flashcards_ai_monthly" \
  APP_STORE_ENVIRONMENT="auto" \
  --project-ref <project-ref>
```

`APP_STORE_ENVIRONMENT` can be `auto`, `production`, or `sandbox`. Use `auto`
for App Review/TestFlight because the function tries production first and then
sandbox.

For temporary local development only, you can set `AI_SUBSCRIPTION_BYPASS=true`.
Do not use that in production.

## Deploy

The iOS app currently sends no Supabase JWT, so deploy without JWT verification:

```bash
npx supabase@latest functions deploy flashcards-ai --project-ref <project-ref> --no-verify-jwt
```

The app setting can be either:

```text
<project-ref>
```

or:

```text
<project-ref>.supabase.co
```

It will call:

```text
https://<project-ref>.supabase.co/functions/v1/flashcards-ai
```

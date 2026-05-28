# Teresa Flashcards

Teresa Flashcards is an iOS flashcard app for personal learning. The app is built around self-created decks, quick review, audio playback, iCloud sync, and optional AI helpers.

The app is intended to be free for manual learning. AI features are unlocked through an optional monthly App Store subscription.

## Current Functionality

- Deck overview with tile-style deck cards.
- Create, edit, and delete decks.
- Select a language for each deck.
- Create questions and answers inside the current deck.
- Deck detail page with deck-specific statistics.
- Separate question list per deck.
- Study view for question and answer review.
- Fixed-size study card layout for more reliable swipe behavior.
- Review states for known, unsure, and repeat-later cards.
- iCloud/Core Data sync when available.
- Audio playback for questions and answers.
- Configurable voice and playback speed.
- Optional AI card generation for the current deck.
- AI answer helpers:
  - simpler explanation
  - example
  - memory aid
  - mini quiz
  - child-friendly explanation
  - exam-style answer
- Apple StoreKit subscription gating for AI features.
- Purchase restore flow.
- Supabase Edge Function backend for AI and subscription verification.
- Public support, FAQ, marketing, and privacy pages.

## Public Links

- Website: https://jwolf-cologne.github.io/teresa-flashcards-site/
- Support: https://jwolf-cologne.github.io/teresa-flashcards-site/support.html
- Privacy Policy: https://jwolf-cologne.github.io/teresa-flashcards-site/privacy.html

## Versioning Plan

- `1.0`: First App Store release.
- `1.0.x`: Bug fixes after release, without meaningful new features.
- `1.1`: First feature update after release, for example improved onboarding, additional language support, better audio controls, or refined AI workflows.
- `2.0`: Reserved for a major product change such as a redesign, account/sharing model, collaboration, or a substantially different learning system.

Every App Store upload also needs a higher build number, even when the public app version stays the same.

## App Store Status

Version `1.0` is in preparation for the first App Store submission.

Before review, App Store Connect needs to stay complete and consistent:

- Current build selected.
- App price set to free.
- AI subscription metadata complete.
- Privacy practices completed.
- Privacy URL set.
- Required screenshots uploaded.
- Review notes explain how Apple can test the AI subscription flow.

## Project Tracking

- Roadmap: [ROADMAP.md](ROADMAP.md)
- Changelog: [CHANGELOG.md](CHANGELOG.md)

## Backend

The Supabase Edge Function lives in:

```text
supabase/functions/flashcards-ai
```

Secrets such as OpenAI keys and App Store private keys must be stored in Supabase secrets only. They must not be committed to this repository.

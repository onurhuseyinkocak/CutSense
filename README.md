# CutSense

Messy recording in. Polished video out.

CutSense takes messy raw talking-head videos, detects mistakes/restarts/repeated takes, creates a clean rough cut, then applies premium captions, motion, SFX, and visual presets locally on iPhone.

## Stack

- **iOS**: Swift 6, SwiftUI, AVFoundation, Speech framework
- **Backend**: Supabase (Auth, Postgres, RLS)
- **Web**: Next.js 16 on Vercel (landing + admin)

## Structure

```
ios/          → Native iOS app (Xcode project)
supabase/     → Database migrations and seed
web/          → Next.js landing/admin
docs/         → Architecture and phase docs
```

## Development

### iOS
```bash
open ios/CutSense.xcodeproj
# or
xcodebuild -scheme CutSense -destination 'platform=iOS Simulator,name=iPhone 16' build
```

### Web
```bash
cd web && pnpm install && pnpm dev
```

### Supabase
Migrations in `supabase/migrations/`. Apply via Supabase CLI or dashboard.

## License

Proprietary. All rights reserved.

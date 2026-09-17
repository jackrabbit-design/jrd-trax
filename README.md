# Trax

## Local setup

Trax needs a Kantata OAuth client secret to sign in. It's kept out of git:

1. Copy the template: `cp TraxApp/Sources/TraxApp/Secrets.swift.example TraxApp/Sources/TraxApp/Secrets.swift`
2. Edit `TraxApp/Sources/TraxApp/Secrets.swift` and replace the placeholder with your real Kantata client secret.

This file is gitignored and never committed.

## Building a release for the team

The "Release build" GitHub Actions workflow (`.github/workflows/release.yml`) builds an ad-hoc-signed `Trax.app` and publishes it as a GitHub Release. To use it:

1. One-time setup: add a `KANTATA_CLIENT_SECRET` repository secret (Settings → Secrets and variables → Actions) with the real Kantata client secret.
2. From the Actions tab, select "Release build" → "Run workflow" to trigger a build manually.
3. On first launch, macOS will show an "unidentified developer" warning — right-click (or Control-click) `Trax.app` and choose **Open** to bypass it.

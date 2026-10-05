# Documentation site

The GitHub Pages site is a buildless collection of HTML pages and local assets in this directory. Its navigation uses relative paths so it works under the repository's Pages base path.

## Local preview

From the repository root, serve this directory with any static HTTP server, for example:

```sh
python3 -m http.server 8000 --directory docs
```

Then open `http://localhost:8000/`.

## Publishing

The `Publish documentation to GitHub Pages` workflow validates local links, fragments, metadata, and image alternatives, then deploys the `docs/` directory when changes reach `main`. In GitHub repository settings, set **Pages → Build and deployment → Source** to **GitHub Actions**. This publishes only the documentation website. The iOS application remains built and distributed through Xcode Cloud.

Before publication, confirm the privacy disclosures, contact address, external service links, and effective dates. Confirm that the in-app links and App Store Connect privacy answers match the published policy. The terms intentionally do not claim a governing-law jurisdiction or legal entity that has not been supplied. Keep screenshots free of credentials and personal data.

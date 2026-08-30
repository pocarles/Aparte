# Third-party notices

## Shipped third-party code

None in V1.

Aparte has no external package dependency and contains no copied source, assets, fonts, or binaries from the reference projects below. Apple system frameworks are supplied under the macOS and Xcode license terms and are not redistributed by this repository.

## Reference projects

These projects informed the architecture review but are not included in Aparte.

### Wisp

- Repository: <https://github.com/sulemaanhamza/wisp>
- Inspected commit: `e4a5c95119aeb8cf822acb103495cd68f2e2d303`
- License: MIT
- Copyright: Copyright (c) 2026 Suleman Hamza

### Inkdown

- Repository: <https://github.com/renardresearch/inkdown>
- Inspected commit: `c5b676791c1a51ec568b789a7925bfe43aea1403`
- License: MIT
- Copyright: Copyright (c) 2026 Seraphine Renard

Inkdown's optional preview includes a JavaScript dependency tree and bundled fonts. Aparte deliberately does not include that preview, those packages, or those assets.

## Release rule

If third-party code or assets enter the product, update this file in the same commit. Record the exact version or commit, copyright notice, license, source URL, modifications, and whether the license text must ship inside the app bundle.


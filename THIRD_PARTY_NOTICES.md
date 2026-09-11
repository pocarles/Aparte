# Third-party notices

## Shipped third-party code

Direct-download builds include [Sparkle](https://github.com/sparkle-project/Sparkle), version 2.9.6, revision `ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a`, under the MIT license. The upstream binary is unchanged apart from code signing. Local and App Store builds do not include it.

The complete upstream license, including notices for Sparkle's bundled components, ships as `Contents/Resources/Sparkle-LICENSE.txt` in direct builds. This notice also ships in that directory. Sparkle's main license follows:

```text
Copyright (c) 2006-2013 Andy Matuschak.
Copyright (c) 2009-2013 Elgato Systems GmbH.
Copyright (c) 2011-2014 Kornel Lesiński.
Copyright (c) 2015-2017 Mayur Pawashe.
Copyright (c) 2014 C.W. Betts.
Copyright (c) 2014 Petroules Corporation.
Copyright (c) 2014 Big Nerd Ranch.
All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

Aparte contains no copied source, assets, fonts, or binaries from the reference projects below. Apple system frameworks are supplied under the macOS and Xcode license terms and are not redistributed by this repository.

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

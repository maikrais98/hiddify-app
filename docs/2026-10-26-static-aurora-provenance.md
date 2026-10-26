# Reference Aurora and efficient motion

Source: exact OpenDesign assets/aurora.svg, viewBox 390x844.
SVG SHA-256: `4003e9498f9f7aacf316a837c78a5493e9f482c9622b64df752e2fccbe5e1dab`.

The glow uses the original two paths, gradients and Gaussian blur14, rasterized once by bundled sharp/librsvg at density288 to1560x3376 and flattened on #07121f. The nine circles are retained separately in SVG using the existing flutter_svg renderer, without filters. No shapes were redrawn.

- Glow PNG SHA-256: `ada99095098dc80acfe368c921688a32c46c169413c27535c460830f2ef8932b`.
- Static stars SVG SHA-256: `c2c093ca125454d960929b5a6d28a2c9daaac071f000aef2f36511838e7b2101`.
- Flattened reference PNG SHA-256: `525fc25c99a37375a33b33def4eb1edd2f88f9550ca8017a0ede0bfb699295c1` (comparison asset).

Split the original `<g fill="#dff5ff">` block into a separate SVG with the original root/viewBox. Remove that block from the glow SVG. Render the remaining glow with `sharp(Buffer.from(glowSvg), {density:288}).flatten({background:'#07121f'}).png()`. Package path: /Users/stasyudkin/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp.

All scenes use cover/topCenter. At the owner's request on 27 October, the cached glow is additionally stretched vertically by 1.4 from the top so its lower light reaches the screen bottom; the original PNG and star coordinates are retained. Only the cached glow image receives the existing motion: angle=phase*2pi, translate(4*sin(angle),2*sin(angle)), scale=1+.008*(1-cos(angle)); one 28s cycle. Initial motion transform is identity. Stars remain static. There are no runtime fragment shaders, animated filters, custom timers or repeated rasterization. Animation pauses under TickerMode/route visibility, modals, inactive lifecycle and reduced-motion/accessibility preferences.

Widget checks confirm visible glow at 90%, 95% and 99% of the portrait viewport height, identical Home/settings composition, glow movement with fixed star pixels, and no scheduled background frames while paused. Physical FPS, device thermal state and native material compositing remain separate device checks; widget evidence alone does not prove them.

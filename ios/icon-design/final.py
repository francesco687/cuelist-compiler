#!/usr/bin/env python3
"""Final Saetta icon (C1: gradient bolt on dark, sliced). Renders 1024 + preview."""
import subprocess, pathlib
HERE = pathlib.Path(__file__).parent
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
BOLT = "M312 120 L312 560 L432 560 L432 920 L712 440 L552 440 L712 120 Z"

SVG = """<svg xmlns="http://www.w3.org/2000/svg" width="SIZE" height="SIZE" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#1d160e"/><stop offset="0.5" stop-color="#15110a"/><stop offset="1" stop-color="#0f0c07"/>
    </linearGradient>
    <linearGradient id="acc" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#f0b860"/><stop offset="1" stop-color="#e0913f"/>
    </linearGradient>
    <filter id="glow" x="-25%" y="-25%" width="150%" height="150%">
      <feGaussianBlur stdDeviation="16" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>
  <rect width="1024" height="1024" fill="url(#bg)"/>
  <g filter="url(#glow)"><path d="BOLT" fill="url(#acc)"/></g>
  <!-- the cut: sever the bolt with bg-colored slice, depth shadow, bright glint -->
  <polygon points="0,504 1024,456 1024,524 0,572" fill="url(#bg)"/>
  <line x1="0" y1="524" x2="1024" y2="476" stroke="#000000" stroke-width="3" opacity="0.45"/>
  <line x1="0" y1="500" x2="1024" y2="452" stroke="#ffe6c0" stroke-width="6" opacity="0.95"/>
</svg>""".replace("BOLT", BOLT)

(HERE / "AppIcon-1024.svg").write_text(SVG.replace("SIZE", "1024"))
for px in (1024, 512):
    name = "AppIcon-1024" if px == 1024 else "final-preview"
    htmlp = HERE / f"{name}.html"
    htmlp.write_text(f"<!doctype html><html><body style='margin:0'>{SVG.replace('SIZE', str(px))}</body></html>")
    out = HERE / f"{name}.png"
    subprocess.run([CHROME, "--headless", "--disable-gpu", "--hide-scrollbars",
                    "--force-device-scale-factor=1", f"--window-size={px},{px}",
                    f"--screenshot={out}", f"file://{htmlp}"], capture_output=True)
    print(name, out.exists())

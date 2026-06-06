#!/usr/bin/env python3
"""Generate Saetta app-icon candidates as SVG -> PNG via Chrome headless."""
import subprocess, os, pathlib

HERE = pathlib.Path(__file__).parent
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# Material-style lightning bolt, scaled/centered into a 1024 box.
# M312 120 L312 560 L432 560 L432 920 L712 440 L552 440 L712 120 Z
BOLT = "M312 120 L312 560 L432 560 L432 920 L712 440 L552 440 L712 120 Z"

DARK_BG = """<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#1b1e26"/><stop offset="0.5" stop-color="#15171c"/>
    <stop offset="1" stop-color="#111319"/></linearGradient>"""
ACCENT = """<linearGradient id="acc" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#7a5cff"/><stop offset="1" stop-color="#5e8bff"/></linearGradient>"""

# The "cut": a slanted slice across the middle. Rendered in bg color to sever the bolt,
# with a thin bright glint edge. y ~ 480..544, slight tilt.
def cut(fill, glint="#cdbcff"):
    return f"""
    <polygon points="0,500 1024,452 1024,520 0,568" fill="{fill}"/>
    <line x1="0" y1="500" x2="1024" y2="452" stroke="{glint}" stroke-width="6" opacity="0.9"/>
    """

def html(svg, px=512):
    return f"<!doctype html><html><body style='margin:0'>{svg.replace('SIZE', str(px))}</body></html>"

# --- Candidate 1: gradient bolt on dark, clean slice ---
c1 = f"""<svg xmlns="http://www.w3.org/2000/svg" width="SIZE" height="SIZE" viewBox="0 0 1024 1024">
  <defs>{DARK_BG}{ACCENT}
    <filter id="glow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="14" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
  </defs>
  <rect width="1024" height="1024" fill="url(#bg)"/>
  <g filter="url(#glow)"><path d="{BOLT}" fill="url(#acc)"/></g>
  <g><polygon points="0,500 1024,452 1024,520 0,568" fill="url(#bg)"/>
     <line x1="0" y1="500" x2="1024" y2="452" stroke="#cdbcff" stroke-width="5" opacity="0.85"/></g>
</svg>"""

# --- Candidate 2: negative bolt on gradient tile ---
c2 = f"""<svg xmlns="http://www.w3.org/2000/svg" width="SIZE" height="SIZE" viewBox="0 0 1024 1024">
  <defs>{ACCENT}
    <linearGradient id="dk" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#15171c"/><stop offset="1" stop-color="#0d0f14"/></linearGradient>
  </defs>
  <rect width="1024" height="1024" fill="url(#acc)"/>
  <path d="{BOLT}" fill="url(#dk)"/>
  <polygon points="0,500 1024,452 1024,520 0,568" fill="url(#acc)"/>
  <line x1="0" y1="500" x2="1024" y2="452" stroke="#ffffff" stroke-width="5" opacity="0.55"/>
</svg>"""

# --- Candidate 3: gradient bolt on dark, halves OFFSET at the cut ---
c3 = f"""<svg xmlns="http://www.w3.org/2000/svg" width="SIZE" height="SIZE" viewBox="0 0 1024 1024">
  <defs>{DARK_BG}{ACCENT}
    <clipPath id="top"><rect x="0" y="0" width="1024" height="496"/></clipPath>
    <clipPath id="bot"><rect x="0" y="544" width="1024" height="480"/></clipPath>
    <filter id="glow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="12" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
  </defs>
  <rect width="1024" height="1024" fill="url(#bg)"/>
  <g filter="url(#glow)">
    <g clip-path="url(#top)"><g transform="translate(-46,0)"><path d="{BOLT}" fill="url(#acc)"/></g></g>
    <g clip-path="url(#bot)"><g transform="translate(46,0)"><path d="{BOLT}" fill="url(#acc)"/></g></g>
  </g>
  <line x1="0" y1="496" x2="1024" y2="496" stroke="#cdbcff" stroke-width="4" opacity="0.5"/>
  <line x1="0" y1="544" x2="1024" y2="544" stroke="#cdbcff" stroke-width="4" opacity="0.5"/>
</svg>"""

cands = {"c1": c1, "c2": c2, "c3": c3}
for name, svg in cands.items():
    (HERE / f"{name}.svg").write_text(svg.replace("SIZE", "1024"))
    htmlpath = HERE / f"{name}.html"
    htmlpath.write_text(html(svg, 512))
    out = HERE / f"{name}.png"
    subprocess.run([CHROME, "--headless", "--disable-gpu", "--hide-scrollbars",
                    "--force-device-scale-factor=1", "--window-size=512,512",
                    f"--screenshot={out}", f"file://{htmlpath}"],
                   capture_output=True)
    print(name, "->", out, out.exists())

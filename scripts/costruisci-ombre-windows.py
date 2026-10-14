#!/usr/bin/env python3
"""Render original Windows preset shadow textures from their SVG sources."""
from pathlib import Path
import subprocess

folder = Path(__file__).resolve().parents[1] / "minerva-shell/windows11/shadows"
folder.mkdir(parents=True, exist_ok=True)
for theme, cast, ambient in (("light", .18, .12), ("dark", .36, .24)):
    svg = folder / f"flyout-{theme}.svg"
    svg.write_text(f'''<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
  <defs>
    <filter id="shadow" x="-50%" y="-50%" width="200%" height="200%" color-interpolation-filters="sRGB">
      <feGaussianBlur in="SourceAlpha" stdDeviation="8" result="blur"/>
      <feOffset in="blur" dy="8" result="cast"/>
      <feComponentTransfer in="cast" result="soft"><feFuncA type="linear" slope="{cast}"/></feComponentTransfer>
      <feGaussianBlur in="SourceAlpha" stdDeviation="1" result="contact"/>
      <feOffset in="contact" dy="2" result="contactOffset"/>
      <feComponentTransfer in="contactOffset" result="ambient"><feFuncA type="linear" slope="{ambient}"/></feComponentTransfer>
      <feMerge result="ombra"><feMergeNode in="soft"/><feMergeNode in="ambient"/></feMerge>
      <!-- L'ombra solo FUORI dalla forma: sotto il pannello non c'è niente.
           Col vetro vero di Windows (Acrylic nel compositore) il pannello
           non si dipinge pieno, e un'ombra anche dentro lo scuriva tutto
           (Claude, 11 ottobre 2026). -->
      <feComposite in="ombra" in2="SourceAlpha" operator="out"/>
    </filter>
  </defs>
  <rect x="32" y="24" width="64" height="64" rx="8" fill="black" filter="url(#shadow)"/>
</svg>
''')
    subprocess.run(["rsvg-convert", "--output", str(svg.with_suffix(".png")), str(svg)], check=True)
    subprocess.run(["rsvg-convert", "--width", "256", "--height", "256", "--output",
                    str(folder / f"flyout-{theme}@2x.png"), str(svg)], check=True)

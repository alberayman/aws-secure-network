"""Render <name>.svg to <name>.png (2x) with headless Chromium. pip install playwright && playwright install chromium"""
import sys, pathlib, re
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    b = p.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    for n in sys.argv[1:]:
        svg = pathlib.Path(n + ".svg").read_text()
        w, h = map(int, re.search(r'width="(\d+)" height="(\d+)"', svg).groups())
        page = pathlib.Path(n + ".render.html")
        page.write_text(f"<!doctype html><html><body style='margin:0'>{svg}</body></html>")
        pg = b.new_page(viewport={"width": w, "height": h}, device_scale_factor=2)
        pg.goto(page.resolve().as_uri(), wait_until="load")
        pg.screenshot(path=n + ".png", clip={"x": 0, "y": 0, "width": w, "height": h}, timeout=60000)
        page.unlink()
    b.close()

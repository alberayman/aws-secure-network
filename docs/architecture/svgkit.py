"""Tiny SVG helper for hand-laid AWS diagrams (icons are the official AWS PNGs from the
`diagrams` package, copied into ./icons)."""
import html

INK = "#232F3E"
FONT = "Helvetica, Arial, sans-serif"


class Svg:
    def __init__(self, w, h, title=None):
        self.w, self.h, self.parts, self.markers = w, h, [], set()
        self.title = title

    def marker(self, color):
        mid = "a" + color.strip("#")
        if mid not in self.markers:
            self.markers.add(mid)
        return mid

    def box(self, x, y, w, h, label, pen, fill="#FFFFFF", dash=False, size=15, bold=True, rx=10, sw=1.8):
        d = ' stroke-dasharray="7 5"' if dash else ""
        self.parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" '
                          f'stroke="{pen}" stroke-width="{sw}"{d}/>')
        if label:
            wt = "700" if bold else "500"
            self.parts.append(f'<text x="{x+14}" y="{y+22}" font-size="{size}" font-weight="{wt}" '
                              f'fill="{INK}">{html.escape(label)}</text>')

    def icon(self, key, cx, cy, label="", size=60, fs=12.5):
        self.parts.append(f'<image href="icons/{key}.png" x="{cx-size/2}" y="{cy-size/2}" '
                          f'width="{size}" height="{size}"/>')
        for i, line in enumerate(label.split("\n") if label else []):
            wt = "600" if i == 0 else "400"
            col = INK if i == 0 else "#545B64"
            self.parts.append(f'<text x="{cx}" y="{cy+size/2+17+i*15}" font-size="{fs}" font-weight="{wt}" '
                              f'fill="{col}" text-anchor="middle">{html.escape(line)}</text>')

    def text(self, x, y, s, size=13, color=INK, anchor="start", weight="400", italic=False):
        it = ' font-style="italic"' if italic else ""
        self.parts.append(f'<text x="{x}" y="{y}" font-size="{size}" font-weight="{weight}" fill="{color}" '
                          f'text-anchor="{anchor}"{it}>{html.escape(s)}</text>')

    def line(self, pts, color, label=None, lpos=None, dash=None, arrow=True, both=False, sw=2.2,
             badge=None, bpos=None):
        d = "M " + " L ".join(f"{x} {y}" for x, y in pts)
        self.path(d, color, label, lpos, dash, arrow, both, sw, badge, bpos)

    def path(self, d, color, label=None, lpos=None, dash=None, arrow=True, both=False, sw=2.2,
             badge=None, bpos=None):
        m = self.marker(color)
        da = f' stroke-dasharray="{dash}"' if dash else ""
        me = f' marker-end="url(#{m})"' if arrow else ""
        ms = f' marker-start="url(#{m}s)"' if both else ""
        self.parts.append(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{sw}" '
                          f'stroke-linejoin="round"{da}{me}{ms}/>')
        if label and lpos:
            self.pill(lpos[0], lpos[1], label, color)
        if badge and bpos:
            self.badge(bpos[0], bpos[1], badge, color)

    def pill(self, x, y, s, color, size=11.5):
        w = 7.0 * len(s) + 14
        self.parts.append(f'<rect x="{x-w/2}" y="{y-10}" width="{w}" height="20" rx="10" fill="#FFFFFF" '
                          f'stroke="{color}" stroke-width="1.2"/>')
        self.parts.append(f'<text x="{x}" y="{y+4}" font-size="{size}" fill="{INK}" '
                          f'text-anchor="middle">{html.escape(s)}</text>')

    def badge(self, x, y, s, color, r=13):
        self.parts.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{color}" stroke="#FFFFFF" stroke-width="2"/>')
        self.parts.append(f'<text x="{x}" y="{y+5}" font-size="14" font-weight="700" fill="#FFFFFF" '
                          f'text-anchor="middle">{html.escape(s)}</text>')

    def cross(self, x, y, color="#D13212", r=12):
        self.parts.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#FFFFFF" stroke="{color}" stroke-width="2.2"/>')
        k = r * 0.5
        self.parts.append(f'<path d="M {x-k} {y-k} L {x+k} {y+k} M {x+k} {y-k} L {x-k} {y+k}" '
                          f'stroke="{color}" stroke-width="2.6" stroke-linecap="round"/>')

    def raw(self, s):
        self.parts.append(s)

    def render(self):
        defs = []
        for m in sorted(self.markers):
            c = "#" + m[1:]
            defs.append(f'<marker id="{m}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
                        f'orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="{c}"/></marker>')
            defs.append(f'<marker id="{m}s" viewBox="0 0 10 10" refX="1" refY="5" markerWidth="7" markerHeight="7" '
                        f'orient="auto"><path d="M10,0 L0,5 L10,10 z" fill="{c}"/></marker>')
        head = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" '
                f'viewBox="0 0 {self.w} {self.h}" font-family="{FONT}">'
                f'<defs>{"".join(defs)}</defs><rect width="100%" height="100%" fill="#FFFFFF"/>')
        return head + "".join(self.parts) + "</svg>"

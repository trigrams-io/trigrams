#!/usr/bin/env python3
"""Generate design assets only. Geometry comes from generate-logo.swift."""
from pathlib import Path
from io import BytesIO
import hashlib
import json
import math
import os
import shutil
import struct
import subprocess
import tempfile
import zipfile
from xml.etree import ElementTree as ET
from xml.sax.saxutils import escape

from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.svgPathPen import SVGPathPen
import uharfbuzz as hb
from PIL import Image

ROOT = Path(__file__).resolve().parent
SSD_TEMP = Path('/Volumes/SSD/Developer/Codex/tmp')
if not Path('/Volumes/SSD').is_mount() or not ROOT.is_relative_to(Path('/Volumes/SSD')):
    raise SystemExit('An SSD-backed checkout and mounted /Volumes/SSD are required.')
SSD_TEMP.mkdir(parents=True, exist_ok=True)
os.environ.update(TMPDIR=str(SSD_TEMP), TMP=str(SSD_TEMP), TEMP=str(SSD_TEMP))
subprocess.run(['swift', '-module-cache-path', str(SSD_TEMP / 'trigrams-sine-brand/swift-cache'),
                str(ROOT / 'generate-logo.swift')], check=True)
GEOMETRY = json.loads((ROOT / 'geometry.json').read_text())
MAIN = GEOMETRY['path']
SMALL = GEOMETRY['smallPath']
THEMES = {
    'light': dict(name='Nano Light', background='#FFFFFF', foreground='#37474F',
                  accent='#673AB7', highlight='#FAFAFA', subtle='#ECEFF1',
                  secondary='#586C76', critical='#FF6F00', popout='#FFAB91',
                  strong='#000000', faded='#B0BEC5'),
    'dark': dict(name='Nano Dark', background='#2E3440', foreground='#ECEFF4',
                 accent='#81A1C1', highlight='#3B4252', subtle='#434C5E',
                 secondary='#B9C3D3', critical='#EBCB8B', popout='#D08770',
                 strong='#ECEFF4', faded='#677691'),
}
GENERATED = set()

font = instantiateVariableFont(TTFont(ROOT / 'source/inter/InterVariable.ttf'),
                               {'wght': 550, 'opsz': 32}, inplace=False)
font_stream = BytesIO()
font.save(font_stream)
hb_font = hb.Font(hb.Face(font_stream.getvalue()))
upm = font['head'].unitsPerEm
hb_font.scale = (upm, upm)
hb.ot_font_set_funcs(hb_font)
glyphs = font.getGlyphSet()


def shape(text, size):
    buffer = hb.Buffer()
    buffer.add_str(text)
    buffer.guess_segment_properties()
    hb.shape(hb_font, buffer)
    scale = size / upm
    cursor = 0
    result = []
    for info, pos in zip(buffer.glyph_infos, buffer.glyph_positions):
        pen = SVGPathPen(glyphs)
        glyphs[font.getGlyphName(info.codepoint)].draw(pen)
        result.append((pen.getCommands(), (cursor + pos.x_offset) * scale, -pos.y_offset * scale))
        cursor += pos.x_advance
    return result, cursor * scale


def text(value, x, baseline, size, color, anchor='start'):
    paths, width = shape(value, size)
    if anchor == 'middle':
        x -= width / 2
    elif anchor == 'end':
        x -= width
    scale = size / upm
    return ''.join(f'<path fill="{color}" transform="translate({x + dx:.4f} {baseline + dy:.4f}) scale({scale:.6f} {-scale:.6f})" d="{d}"/>'
                   for d, dx, dy in paths if d)


def mark(color, x=0, y=0, size=256, small=False):
    return f'<g transform="translate({x} {y}) scale({size / 256:.6f})"><path fill="{color}" d="{SMALL if small else MAIN}"/></g>'


def svg(body, width, height, title, background=None):
    bg = f'<rect width="{width}" height="{height}" fill="{background}"/>' if background else ''
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}" role="img" aria-label="{escape(title)}">\n{bg}{body}\n</svg>\n'


def write(relative, content):
    path = ROOT / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(content, bytes):
        path.write_bytes(content)
    else:
        path.write_text(content)
    GENERATED.add(path)
    return path


def render(source, width=None, height=None, output=None):
    output = output or source.with_suffix('.png')
    args = ['rsvg-convert', '-o', str(output)]
    if width:
        args += ['-w', str(width)]
    if height:
        args += ['-h', str(height)]
    subprocess.run(args + [str(source)], check=True)
    GENERATED.add(output)
    return output


def embed(source, x, y, width, height):
    root = ET.fromstring(source.read_text())
    viewbox = root.attrib['viewBox']
    body = ''.join(ET.tostring(child, encoding='unicode') for child in root)
    return f'<svg x="{x}" y="{y}" width="{width}" height="{height}" viewBox="{viewbox}">{body}</svg>'


def ico(paths):
    payloads = [p.read_bytes() for p in paths]
    offset = 6 + len(paths) * 16
    entries = []
    for path, data in zip(paths, payloads):
        with Image.open(path) as image:
            w, h = image.size
        entries.append(struct.pack('<BBBBHHII', w if w < 256 else 0, h if h < 256 else 0,
                                   0, 0, 1, 32, len(data), offset))
        offset += len(data)
    return struct.pack('<HHH', 0, 1, len(paths)) + b''.join(entries) + b''.join(payloads)


horizontal_width = math.ceil((208 + shape('Trigrams', 88)[1] + 24) / 8) * 8
for key, theme in THEMES.items():
    for finish in ['transparent', 'solid']:
        background = theme['background'] if finish == 'solid' else None
        source = write(f'assets/logo/mark-{key}-{finish}.svg',
                       svg(mark(theme['accent']), 256, 256, f'Trigrams / {theme["name"]} / {finish}', background))
        render(source, width=1024, height=1024)
        for layout in ['horizontal', 'stacked', 'wordmark']:
            if layout == 'horizontal':
                width, height = horizontal_width, 192
                body = mark(theme['accent'], 16, 12, 168) + text('Trigrams', 208, 124, 88, theme['foreground'])
            elif layout == 'stacked':
                width, height = 512, 384
                body = mark(theme['accent'], 116, 4, 280) + text('Trigrams', 256, 314, 64, theme['foreground'], 'middle')
            else:
                width, height = math.ceil((shape('Trigrams', 88)[1] + 48) / 8) * 8, 144
                body = text('Trigrams', 24, 100, 88, theme['foreground'])
            source = write(f'assets/wordmark/{layout}-{key}-{finish}.svg',
                           svg(body, width, height, f'Trigrams {layout} / {theme["name"]} / {finish}', background))
            render(source, width=2048)
    source = write(f'assets/logo/mark-{key}-ink.svg', svg(mark(theme['foreground']), 256, 256, f'Trigrams / {theme["name"]} ink'))
    render(source, width=1024, height=1024)

    # Native macOS icon: transparent outer margin, precomposed rounded container.
    body = f'<rect x="64" y="64" width="896" height="896" rx="200" fill="{theme["background"]}"/>'
    body += mark(theme['accent'], 154, 154, 716)
    icon_source = write(f'assets/app-icon/trigrams-{key}.svg', svg(body, 1024, 1024, f'Trigrams app icon / {theme["name"]}'))
    render(icon_source, width=1024, height=1024)
    catalog = ROOT / f'assets/app-icon/AppIcon-{key.capitalize()}.appiconset'
    records = []
    with tempfile.TemporaryDirectory(prefix='trigrams-icon.', dir=SSD_TEMP) as temp:
        iconset = Path(temp) / 'Trigrams.iconset'
        iconset.mkdir()
        for logical in [16, 32, 128, 256, 512]:
            for scale in [1, 2]:
                pixels = logical * scale
                filename = f'icon_{logical}x{logical}{"@2x" if scale == 2 else ""}.png'
                path = catalog / filename
                path.parent.mkdir(parents=True, exist_ok=True)
                # Slightly heavier geometry only for the smallest icon slot.
                icon_input = icon_source
                if pixels == 16:
                    optical = body.replace(MAIN, SMALL)
                    icon_input = Path(temp) / 'optical.svg'
                    icon_input.write_text(svg(optical, 1024, 1024, 'Trigrams small app icon'))
                render(icon_input, width=pixels, height=pixels, output=path)
                shutil.copyfile(path, iconset / filename)
                records.append({'idiom': 'mac', 'size': f'{logical}x{logical}', 'scale': f'{scale}x', 'filename': filename})
        write(f'assets/app-icon/AppIcon-{key.capitalize()}.appiconset/Contents.json',
              json.dumps({'images': records, 'info': {'version': 1, 'author': 'Trigrams'}}, indent=2) + '\n')
        icns_path = ROOT / f'assets/app-icon/Trigrams-{key.capitalize()}.icns'
        subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(icns_path)], check=True)
        GENERATED.add(icns_path)

    # Browser favicon, web app icons, and Apple touch icon are separate exports.
    favicon_source = write(f'assets/favicon/{key}/favicon.svg', svg(mark(theme['accent'], small=True), 256, 256, f'Trigrams favicon / {theme["name"]}'))
    favicon_pngs = []
    for size in [16, 32, 48]:
        output = ROOT / f'assets/favicon/{key}/favicon-{size}.png'
        render(favicon_source, width=size, height=size, output=output)
        favicon_pngs.append(output)
    write(f'assets/favicon/{key}/favicon.ico', ico(favicon_pngs))
    web_source = write(f'assets/favicon/{key}/web-icon.svg',
                       svg(mark(theme['accent']), 256, 256, f'Trigrams web icon / {theme["name"]}', theme['background']))
    for size, name in [(180, 'apple-touch-icon'), (192, 'icon-192'), (512, 'icon-512')]:
        render(web_source, width=size, height=size, output=ROOT / f'assets/favicon/{key}/{name}.png')
    mask_source = write(f'assets/favicon/{key}/maskable.svg',
                        svg(mark(theme['accent'], 28.16, 28.16, 199.68), 256, 256, f'Trigrams maskable icon / {theme["name"]}', theme['background']))
    render(mask_source, width=512, height=512, output=ROOT / f'assets/favicon/{key}/maskable-512.png')
    webmanifest = {'name': 'Trigrams', 'short_name': 'Trigrams', 'display': 'standalone',
                   'theme_color': theme['background'], 'background_color': theme['background'],
                   'icons': [{'src': 'icon-192.png', 'sizes': '192x192', 'type': 'image/png'},
                             {'src': 'icon-512.png', 'sizes': '512x512', 'type': 'image/png'},
                             {'src': 'maskable-512.png', 'sizes': '512x512', 'type': 'image/png', 'purpose': 'maskable'}]}
    write(f'assets/favicon/{key}/site.webmanifest', json.dumps(webmanifest, indent=2) + '\n')

    # Auxiliary three-phase sine graphic, kept separate from the primary mark.
    curves = []
    for phase in [0, 2 * math.pi / 3, 4 * math.pi / 3]:
        points = [(1200 * t / 384, 300 - 148 * math.sin(4 * math.pi * t / 384 + phase)) for t in range(385)]
        d = ' '.join(f'{"M" if i == 0 else "L"}{x:.4f} {y:.4f}' for i, (x, y) in enumerate(points))
        curves.append(f'<path d="{d}" fill="none" stroke="{theme["accent"]}" stroke-width="4" opacity="0.32"/>')
    pattern = write(f'assets/pattern/sine-{key}.svg', svg(''.join(curves), 1200, 600, f'Trigrams three-phase pattern / {theme["name"]}', theme['background']))
    render(pattern, width=1600)
    social = mark(theme['accent'], 88, 172, 280) + text('Trigrams', 400, 344, 112, theme['foreground'])
    social += text('A native macOS agent.', 405, 408, 28, theme['secondary'])
    social_source = write(f'assets/social/og-{key}.svg', svg(social, 1200, 630, f'Trigrams social card / {theme["name"]}', theme['background']))
    render(social_source, width=1200, height=630)

for name, color in [('black', '#000000'), ('white', '#FFFFFF')]:
    source = write(f'assets/logo/mark-mono-{name}.svg', svg(mark(color), 256, 256, f'Trigrams monochrome / {name}'))
    render(source, width=1024, height=1024)

adaptive = '<style>.wave{fill:#673AB7}@media(prefers-color-scheme:dark){.wave{fill:#81A1C1}}</style>'
adaptive += f'<path class="wave" d="{SMALL}"/>'
write('assets/favicon/favicon.svg', svg(adaptive, 256, 256, 'Trigrams adaptive favicon'))
write('palette.json', json.dumps({'name': 'Trigrams', 'reference': 'Nano Emacs', 'themes': THEMES}, indent=2) + '\n')
css = []
for key, theme in THEMES.items():
    selector = ':root, [data-trigrams-theme="light"]' if key == 'light' else '[data-trigrams-theme="dark"]'
    css.append(selector + ' {\n' + ''.join(f'  --trigrams-{name}: {value};\n' for name, value in theme.items() if name != 'name') + '}\n')
write('palette.css', '\n'.join(css))

# Review board. All lettering is outlined, so no font installation is needed.
board = '<defs><pattern id="alpha-light" width="20" height="20" patternUnits="userSpaceOnUse"><rect width="20" height="20" fill="#FFFFFF"/><path d="M0 0H10V10H0ZM10 10H20V20H10Z" fill="#ECEFF1"/></pattern><pattern id="alpha-dark" width="20" height="20" patternUnits="userSpaceOnUse"><rect width="20" height="20" fill="#2E3440"/><path d="M0 0H10V10H0ZM10 10H20V20H10Z" fill="#3B4252"/></pattern></defs>'
for index, (key, theme) in enumerate(THEMES.items()):
    pane = f'<rect width="800" height="940" fill="{theme["background"]}"/>'
    pane += text(theme['name'].upper(), 40, 48, 16, theme['secondary'])
    pane += mark(theme['accent'], 272, 70, 256)
    pane += embed(ROOT / f'assets/wordmark/horizontal-{key}-transparent.svg', 130, 346, 540, 164)
    pane += f'<rect x="40" y="554" width="184" height="164" fill="url(#alpha-{key})"/>'
    pane += mark(theme['accent'], 68, 572, 128)
    pane += f'<rect x="270" y="554" width="184" height="164" fill="{theme["background"]}" stroke="{theme["subtle"]}"/>'
    pane += mark(theme['accent'], 298, 572, 128)
    pane += f'<rect x="508" y="554" width="184" height="164" fill="{theme["subtle"]}"/>'
    pane += embed(ROOT / f'assets/app-icon/trigrams-{key}.svg', 518, 554, 164, 164)
    for x, label in [(132, 'Transparent'), (362, 'Solid'), (600, 'macOS icon')]:
        pane += text(label, x, 748, 15, theme['secondary'], 'middle')
    pane += text('FAVICON', 40, 822, 13, theme['secondary'])
    for x, size in [(232, 16), (352, 32), (492, 48)]:
        pane += mark(theme['accent'], x - size / 2, 800 - size / 2, size, small=True)
        pane += text(f'{size} px', x, 850, 12, theme['secondary'], 'middle')
    pane += text(f'{theme["accent"]}  /  {theme["foreground"]}  /  {theme["background"]}', 40, 906, 12, theme['secondary'])
    board += f'<g transform="translate({index * 800} 0)">{pane}</g>'
preview = write('trigrams-preview.svg', svg(board, 1600, 940, 'Trigrams brand kit / Nano Light and Nano Dark'))
render(preview, width=1600, height=940)

construction = '<defs><pattern id="grid" width="24" height="24" patternUnits="userSpaceOnUse"><path d="M24 0H0V24" fill="none" stroke="#81A1C1" opacity="0.12"/></pattern></defs><rect width="1120" height="640" fill="url(#grid)"/>'
construction += text('TRIGRAMS / SINE CONSTRUCTION', 40, 48, 18, '#ECEFF4')
construction += f'<g transform="translate(28 104) scale(1.8)"><path d="{MAIN}" fill="#81A1C1" opacity="0.24"/><path d="{GEOMETRY["centerline"]}" fill="none" stroke="#ECEFF4" stroke-width="0.8"/><path d="M16 128H240 M128 32V224" fill="none" stroke="#81A1C1" stroke-width="0.5" stroke-dasharray="3 3"/></g>'
for value, x, y, size, color in [
    ('01 / One true sine period', 568, 164, 20, '#ECEFF4'),
    ('x(t) = 32 + 192t', 568, 204, 17, '#B9C3D3'),
    ('y(t) = 128 - 64 sin(2πt)', 568, 234, 17, '#B9C3D3'),
    ('02 / Controlled line weight', 568, 322, 20, '#ECEFF4'),
    ('r(t) = 9 + 4 sin²(πt)', 568, 362, 17, '#B9C3D3'),
    ('Circular end caps / analytic normals', 568, 392, 16, '#B9C3D3'),
    ('03 / Optical small-size variant', 568, 480, 20, '#ECEFF4'),
    ('L = 208, A = 56, r = 11 + 3 sin²(πt)', 568, 520, 15, '#B9C3D3'),
    ('Deterministic geometry / no font dependency in exported SVGs', 40, 600, 14, '#B9C3D3'),
]:
    construction += text(value, x, y, size, color)
source = write('trigrams-construction.svg', svg(construction, 1120, 640, 'Trigrams sine geometry', '#2E3440'))
render(source, width=1120, height=640)

# Root compatibility exports and source files belong to the kit as well.
GENERATED.update(ROOT / name for name in ['geometry.json', 'trigrams-mark.svg', 'trigrams-mark-light.svg', 'trigrams-mark-dark.svg'])
for path in sorted(GENERATED):
    if path.suffix == '.svg':
        tree = ET.parse(path)
        assert not tree.findall('.//{http://www.w3.org/2000/svg}text'), path
        assert not tree.findall('.//{http://www.w3.org/2000/svg}script'), path

records = []
for path in sorted(GENERATED):
    record = {'path': str(path.relative_to(ROOT)), 'bytes': path.stat().st_size,
              'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    if path.suffix == '.png':
        with Image.open(path) as image:
            record.update(width=image.width, height=image.height, mode=image.mode)
    records.append(record)
write('asset-manifest.json', json.dumps({'brand': 'Trigrams', 'version': 'sine-1', 'themes': list(THEMES), 'files': records}, indent=2) + '\n')
print(f'Generated {len(records)} assets and metadata files in {ROOT}.')

# Bundle assets, source inputs and guidance with stable archive metadata.
members = set(GENERATED)
members.update(path for path in (ROOT / 'source').rglob('*') if path.is_file())
members.update(ROOT / name for name in ['README.md', 'generate-logo.swift', 'generate-brand.py', 'requirements.txt'])
archive = ROOT / 'Trigrams-Brand-Kit.zip'
with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
    for path in sorted(members):
        info = zipfile.ZipInfo('Trigrams-Brand-Kit/' + str(path.relative_to(ROOT)), date_time=(2026, 10, 4, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o100644 << 16
        content = path.read_bytes()
        if path == ROOT / 'README.md':
            content = content.replace('[下载完整物料包](Trigrams-Brand-Kit.zip) · '.encode(), b'')
        bundle.writestr(info, content)
print(f'Packaged {len(members)} files in {archive.name}.')

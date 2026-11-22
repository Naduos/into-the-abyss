#!/usr/bin/env python3
"""Setzt das Programmsymbol der exportierten Windows-exe (ohne rcedit/Wine).
   Die Godot-Exportvorlage enthält schon ein Symbol in 6 Größen (16–256 px). Dieses Skript
   überschreibt die Bilddaten an Ort und Stelle mit icon.png (gleiche Größen, gleiche Länge;
   256 px als PNG, das kleiner sein muss als der vorhandene Platz).
   Aufruf: python3 tools/set_exe_icon.py <exe> <icon.png>"""
import io, struct, sys
import pefile
from PIL import Image

exe, png = sys.argv[1], sys.argv[2]
src = Image.open(png).convert('RGBA')
pe = pefile.PE(exe, fast_load=True)
pe.parse_data_directories(directories=[pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_RESOURCE']])
data = bytearray(pe.__data__)

def entries(type_id):
    for t in pe.DIRECTORY_ENTRY_RESOURCE.entries:
        if t.id == type_id:
            for e in t.directory.entries:
                for lang in e.directory.entries:
                    yield e.id, lang.data.struct
icons = {i: s for i, s in entries(pefile.RESOURCE_TYPE['RT_ICON'])}
groups = list(entries(pefile.RESOURCE_TYPE['RT_GROUP_ICON']))

def dib(img):                                   # 32-Bit-Bitmap + leere AND-Maske (Alpha zählt)
    w, h = img.size
    px = img.transpose(Image.FLIP_TOP_BOTTOM).tobytes('raw', 'BGRA')
    mask = b'\0' * (((w + 31) // 32) * 4 * h)
    return struct.pack('<IiiHHIIiiII', 40, w, h * 2, 1, 32, 0, len(px) + len(mask), 0, 0, 0, 0) + px + mask

gid, gs = groups[0]
off = pe.get_offset_from_rva(gs.OffsetToData)
hdr = struct.unpack_from('<HHH', data, off)
count = hdr[2]
for k in range(count):
    p = off + 6 + k * 14
    bw, bh, cc, res, planes, bpp, nbytes, icon_id = struct.unpack_from('<BBBBHHIH', data, p)
    size = bw or 256
    s = icons[icon_id]
    img = src.resize((size, size), Image.LANCZOS)
    if size >= 256:
        buf = io.BytesIO(); img.save(buf, 'PNG', optimize=True); blob = buf.getvalue()
    else:
        blob = dib(img)
    if len(blob) > s.Size:
        sys.exit(f'Symbol {size}px zu groß ({len(blob)} > {s.Size})')
    doff = pe.get_offset_from_rva(s.OffsetToData)
    data[doff:doff + s.Size] = blob + b'\0' * (s.Size - len(blob))
    # neue Länge im Ressourcen-Eintrag und in der Symbolgruppe
    struct.pack_into('<I', data, s.get_file_offset() + 4, len(blob))
    struct.pack_into('<I', data, p + 8, len(blob))
    print(f'{size:>3}px: {len(blob)} Bytes')
open(exe, 'wb').write(bytes(data))
print('Symbol gesetzt:', exe)

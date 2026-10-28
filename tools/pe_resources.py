#!/usr/bin/env python3
"""Replace the icon and version info inside a Windows .exe (PE32+) without rcedit.

Used to brand the Godot export template before the game data is embedded:

    python3 tools/pe_resources.py IN.exe OUT.exe --icon branding/game.ico \
        --version 1.3.0.0 --company Ironite --product "The Appalachian Trail" \
        --description "The Appalachian Trail" --copyright "(c) 2026 Ironite" \
        --original AppalachianTrail.exe

The rebuilt resource tree must fit in the space the template reserves for .rsrc
(Godot's default icon is large, so a normal multi-size .ico fits comfortably).
Other resources (e.g. the application manifest) are preserved.
"""
import argparse
import struct
import sys

RT_ICON, RT_GROUP_ICON, RT_VERSION = 3, 14, 16


# ------------------------------------------------------------------ PE helpers

class PE:
    def __init__(self, data):
        self.d = bytearray(data)
        pe = struct.unpack_from("<I", self.d, 0x3C)[0]
        self.nsec = struct.unpack_from("<H", self.d, pe + 6)[0]
        optsz = struct.unpack_from("<H", self.d, pe + 20)[0]
        self.opt = pe + 24
        magic = struct.unpack_from("<H", self.d, self.opt)[0]
        if magic != 0x20B:
            sys.exit("only PE32+ executables are supported")
        self.falign = struct.unpack_from("<I", self.d, self.opt + 36)[0]
        self.dd = self.opt + 112
        self.sh = self.opt + optsz
        self.sections = []
        for i in range(self.nsec):
            off = self.sh + i * 40
            name, vs, va, rs, ro = struct.unpack_from("<8sIIII", self.d, off)
            self.sections.append(dict(name=name.rstrip(b"\0"), vs=vs, va=va, rs=rs, ro=ro, hdr=off))

    def rsrc(self):
        rva, size = struct.unpack_from("<II", self.d, self.dd + 2 * 8)
        for i, s in enumerate(self.sections):
            if s["va"] == rva:
                return i, s, size
        sys.exit(".rsrc section not found")


# ------------------------------------------------------------------ resource tree parse

def parse_tree(d, base_off, base_rva):
    def name_of(raw):
        if raw & 0x80000000:
            p = base_off + (raw & 0x7FFFFFFF)
            n = struct.unpack_from("<H", d, p)[0]
            return d[p + 2:p + 2 + n * 2].decode("utf-16-le")
        return raw

    def walk(off, depth):
        _, _, _, _, nn, ni = struct.unpack_from("<IIHHHH", d, base_off + off)
        out = []
        for k in range(nn + ni):
            raw, target = struct.unpack_from("<II", d, base_off + off + 16 + k * 8)
            key = name_of(raw)
            if target & 0x80000000:
                out.append((key, walk(target & 0x7FFFFFFF, depth + 1)))
            else:
                rva, size, cp, _ = struct.unpack_from("<IIII", d, base_off + target)
                blob = bytes(d[base_off + (rva - base_rva): base_off + (rva - base_rva) + size])
                out.append((key, (blob, cp)))
        return out

    return walk(0, 0)


# ------------------------------------------------------------------ resource tree build

def build_tree(tree, base_rva):
    """tree: [(key, subtree | (blob, codepage))] three levels deep -> bytes"""
    dirs = bytearray()
    entries_fix = []      # (pos_in_dirs, kind, ref)
    leaves = []
    strings = []

    # breadth-first layout of directory tables
    layout = []

    def plan(node):
        idx = len(layout)
        layout.append(node)
        return idx

    queue = [tree]
    order = []
    while queue:
        node = queue.pop(0)
        order.append(node)
        for _, child in node:
            if isinstance(child, list):
                queue.append(child)

    dir_off = {}
    pos = 0
    for node in order:
        dir_off[id(node)] = pos
        pos += 16 + 8 * len(node)
    dirs_size = pos

    leaf_list = []
    for node in order:
        for _, child in node:
            if not isinstance(child, list):
                leaf_list.append(child)
    leaf_off = {}
    for i, leaf in enumerate(leaf_list):
        leaf_off[id(leaf)] = dirs_size + i * 16
    strings_start = dirs_size + 16 * len(leaf_list)

    str_blob = bytearray()
    str_off = {}
    for node in order:
        for key, _ in node:
            if isinstance(key, str) and key not in str_off:
                str_off[key] = strings_start + len(str_blob)
                enc = key.encode("utf-16-le")
                str_blob += struct.pack("<H", len(key)) + enc
    data_start = strings_start + len(str_blob)
    data_start = (data_start + 7) & ~7

    data_blob = bytearray()
    data_rel = {}
    for leaf in leaf_list:
        data_rel[id(leaf)] = data_start + len(data_blob)
        data_blob += leaf[0]
        while len(data_blob) % 8:
            data_blob += b"\0"

    out = bytearray(data_start + len(data_blob))
    for node in order:
        o = dir_off[id(node)]
        named = [e for e in node if isinstance(e[0], str)]
        ids = sorted([e for e in node if not isinstance(e[0], str)], key=lambda e: e[0])
        named.sort(key=lambda e: e[0].upper())
        struct.pack_into("<IIHHHH", out, o, 0, 0, 4, 0, len(named), len(ids))
        for k, (key, child) in enumerate(named + ids):
            raw = (str_off[key] | 0x80000000) if isinstance(key, str) else key
            target = (dir_off[id(child)] | 0x80000000) if isinstance(child, list) else leaf_off[id(child)]
            struct.pack_into("<II", out, o + 16 + k * 8, raw, target)
    for leaf in leaf_list:
        o = leaf_off[id(leaf)]
        struct.pack_into("<IIII", out, o, base_rva + data_rel[id(leaf)], len(leaf[0]), leaf[1], 0)
    out[strings_start:strings_start + len(str_blob)] = str_blob
    out[data_start:] = data_blob
    return bytes(out)


# ------------------------------------------------------------------ icon + version builders

def load_ico(path):
    d = open(path, "rb").read()
    _, typ, count = struct.unpack_from("<HHH", d, 0)
    if typ != 1:
        sys.exit("not an .ico file")
    images = []
    for i in range(count):
        w, h, cc, res, planes, bpp, size, off = struct.unpack_from("<BBBBHHII", d, 6 + i * 16)
        images.append(dict(w=w, h=h, cc=cc, planes=planes or 1, bpp=bpp or 32, data=d[off:off + size]))
    return images


def group_icon(images, first_id):
    out = struct.pack("<HHH", 0, 1, len(images))
    for i, im in enumerate(images):
        out += struct.pack("<BBBBHHIH", im["w"], im["h"], im["cc"], 0, im["planes"], im["bpp"], len(im["data"]), first_id + i)
    return out


def _pad32(b):
    while len(b) % 4:
        b += b"\0"
    return b


def _block(key, value=b"", wtype=1, children=b"", value_len=None):
    k = (key + "\0").encode("utf-16-le")
    body = bytearray(struct.pack("<HHH", 0, 0, wtype)) + k
    body = _pad32(body)
    body += value
    body = _pad32(body)
    body += children
    if value_len is None:
        value_len = len(value) // 2 if wtype == 1 else len(value)
    struct.pack_into("<HH", body, 0, len(body), value_len)
    return bytes(body)


def version_info(ver, strings):
    parts = [int(x) for x in (ver.split(".") + ["0"] * 4)[:4]]
    ms = (parts[0] << 16) | parts[1]
    ls = (parts[2] << 16) | parts[3]
    fixed = struct.pack("<13I", 0xFEEF04BD, 0x00010000, ms, ls, ms, ls, 0x3F, 0, 0x00040004, 1, 0, 0, 0)
    table = b""
    for k, v in strings.items():
        val = (v + "\0").encode("utf-16-le")
        table += _pad32(bytearray(_block(k, val, 1)))
    st = _block("040904b0", b"", 1, table, 0)
    sfi = _block("StringFileInfo", b"", 1, _pad32(bytearray(st)), 0)
    var = _block("Translation", struct.pack("<HH", 0x0409, 0x04B0), 0)
    vfi = _block("VarFileInfo", b"", 1, _pad32(bytearray(var)), 0)
    root = _block("VS_VERSION_INFO", fixed, 0, _pad32(bytearray(sfi)) + vfi, len(fixed))
    return root


# ------------------------------------------------------------------ main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("inp")
    ap.add_argument("out")
    ap.add_argument("--icon", required=True)
    ap.add_argument("--version", default="1.0.0.0")
    ap.add_argument("--company", default="")
    ap.add_argument("--product", default="")
    ap.add_argument("--description", default="")
    ap.add_argument("--copyright", default="")
    ap.add_argument("--original", default="")
    a = ap.parse_args()

    pe = PE(open(a.inp, "rb").read())
    idx, sec, cur_size = pe.rsrc()
    tree = parse_tree(pe.d, sec["ro"], sec["va"])
    lang = 1033
    for key, sub in tree:
        if isinstance(sub, list) and sub and isinstance(sub[0][1], list) and sub[0][1]:
            lang = sub[0][1][0][0]
            break

    images = load_ico(a.icon)
    new = [(k, v) for (k, v) in tree if k not in (RT_ICON, RT_GROUP_ICON, RT_VERSION)]
    new.append((RT_ICON, [(i + 1, [(lang, (im["data"], 0))]) for i, im in enumerate(images)]))
    # keep the original group-icon name (Godot loads "GODOT_ICON" for its window icon)
    group_key = 1
    for k, sub in tree:
        if k == RT_GROUP_ICON and sub:
            group_key = sub[0][0]
    new.append((RT_GROUP_ICON, [(group_key, [(lang, (group_icon(images, 1), 0))])]))
    vi = version_info(a.version, {
        "CompanyName": a.company, "FileDescription": a.description, "FileVersion": a.version,
        "InternalName": a.original.rsplit(".", 1)[0], "LegalCopyright": a.copyright,
        "OriginalFilename": a.original, "ProductName": a.product, "ProductVersion": a.version,
    })
    new.append((RT_VERSION, [(1, [(lang, (vi, 0))])]))
    new.sort(key=lambda e: (isinstance(e[0], str), e[0] if not isinstance(e[0], str) else 0))

    blob = build_tree(new, sec["va"])
    # space available: up to the next section's virtual address, and the raw size on disk
    next_va = min(s["va"] for s in pe.sections if s["va"] > sec["va"])
    max_virtual = next_va - sec["va"]
    if len(blob) > sec["rs"] or len(blob) > max_virtual:
        sys.exit(f"new resources ({len(blob)} bytes) do not fit in .rsrc ({sec['rs']} bytes); use a smaller icon")
    d = pe.d
    d[sec["ro"]:sec["ro"] + sec["rs"]] = blob + b"\0" * (sec["rs"] - len(blob))
    struct.pack_into("<I", d, sec["hdr"] + 8, len(blob))           # VirtualSize
    struct.pack_into("<I", d, pe.dd + 2 * 8 + 4, len(blob))          # resource directory size
    struct.pack_into("<I", d, pe.opt + 64, 0)                        # clear checksum
    open(a.out, "wb").write(d)
    print(f"patched resources: {len(images)} icon images, version {a.version}, {len(blob)}/{sec['rs']} bytes used")


if __name__ == "__main__":
    main()

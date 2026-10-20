# Build an ath10k board-2.bin from the stock icnss2 board files, keyed the
# way icnss2 picks them: bdwlan.b<id> (id < 0xff), bdwlan.<id> (id > 0xff),
# bdwlan.bin for board id 0xff.  usage: ath10k-bd.py <bdwlan dir> <out>
import os, re, struct, sys

def ie(ie_id, data):
    pad = (-len(data)) % 4
    return struct.pack('<II', ie_id, len(data)) + data + b'\0' * pad

src, out = sys.argv[1], sys.argv[2]
boards = []
for fn in sorted(os.listdir(src)):
    m = re.fullmatch(r'bdwlan\.(b[0-9a-f]{2}|[0-9a-f]{3}|bin)', fn)
    if not m:
        continue
    tag = m.group(1)
    board_id = 0xff if tag == 'bin' else int(tag.lstrip('b'), 16)
    data = open(os.path.join(src, fn), 'rb').read()
    boards.append((f'bus=snoc,qmi-board-id={board_id:x}', data, fn))

magic = b'QCA-ATH10K-BOARD\0'
blob = magic + b'\0' * ((-len(magic)) % 4)
for name, data, fn in boards:
    blob += ie(0, ie(0, name.encode()) + ie(1, data))
    print(f'{name:32s} <- {fn}')
open(out, 'wb').write(blob)

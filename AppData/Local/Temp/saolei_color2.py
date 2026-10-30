# -*- coding: utf-8 -*-
"""Sample dominant opaque colours of the trip fireball and the disarm beam."""
from collections import Counter
from PIL import Image

RAW = r"C:\Users\19161\saolei\entry\src\main\resources\rawfile"
other = Image.open(RAW + r"\otherSheet.png").convert("RGBA")

def top_colors(box, n=6):
    reg = other.crop(box)
    px = [p for p in reg.get_flattened_data() if p[3] > 200]
    c = Counter(px)
    return c.most_common(n)

print("trip frame 4 (fireball, px 1574,118 114x114):")
for p, n in top_colors((1574, 118, 1688, 232)):
    print("   ", p, n)

print("\ntrip frame 0 (mine, px 1456,0 114x114):")
for p, n in top_colors((1456, 0, 1570, 114)):
    print("   ", p, n)

print("\ndisarm frame 6 (beam, px 624,0 100x300):")
for p, n in top_colors((624, 0, 724, 300)):
    print("   ", p, n)

print("\nscan bar strongest opaque px:")
bar = other.crop((0, 1824, 550, 1948))
px = [p for p in bar.get_flattened_data() if p[3] > 240]
print("   ", Counter(px).most_common(4))

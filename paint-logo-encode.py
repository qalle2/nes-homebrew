"""Convert the Kalle Paint logo from PNG into binary data (NES tile indexes)."""

import sys
from PIL import Image  # Pillow

SOURCE_FILE = "paint-logo.png"
TARGET_FILE = "paint-logo.bin"
PNG_COLOR_TO_NES_COLOR = {  # RGB -> NES color (0-3)
    (0xff, 0xff, 0xff): 1,
    (0x00, 0x00, 0x00): 2,
    (0x80, 0x80, 0x80): 3,
}

def validate_image(img):
    """img: Pillow image; exit on error"""

    if img.width != 64 or img.height != 6:
        sys.exit("The image must be 64*6 pixels.")

    if img.mode != "RGB":
        sys.exit("The image must be in RGB format.")

    for y in range(img.height):
        for x in range(img.width):
            color = img.getpixel((x, y))
            if color not in PNG_COLOR_TO_NES_COLOR:
                sys.exit(f"Unknown color: {color}")

def encode_image(img):
    """Read 64*6 RGB pixels, convert them into 2-bit NES colors, convert them into 3*32 bytes
    (NES tile indexes).
    1 byte = 2*2 pixels:
        - bits: AaBbCcDd
        - pixels: Aa = upper left, Bb = upper right, Cc = lower left, Dd = lower right
        - capital letter = MSB, small letter = LSB
    img: Pillow image
    yield: 32 bytes per call"""

    encoded = bytearray()  # row of encoded bytes

    # encode 3*32 hexadecimal bytes (64*6 pixels)
    for bi in range(3 * 32):  # target byte index (bits: YYX XXXX)
        # encode 1 byte (2*2 pixels)
        byte = 0
        for pi in range(4):  # source pixel index (bits: yx)
            y = bi >> 4 & 0x06 | pi >> 1  # bits: YYy
            x = bi << 1 & 0x3e | pi & 1   # bits: XX XXXx
            byte = byte << 2 | PNG_COLOR_TO_NES_COLOR[img.getpixel((x, y))]
        encoded.append(byte)
        if bi & 0x1f == 0x1f:
            yield encoded
            encoded.clear()

def main():
    """The main function."""

    try:
        with open(SOURCE_FILE, "rb") as source:
            source.seek(0)
            img = Image.open(source)
            validate_image(img)
            with open(TARGET_FILE, "wb") as target:
                target.seek(0)
                for row in encode_image(img):
                    target.write(row)
    except OSError:
        sys.exit("Error reading/writing files.")

    print(f"{TARGET_FILE} written.")

if __name__ == "__main__":
    main()


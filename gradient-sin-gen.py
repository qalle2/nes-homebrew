# generate sine table for NES Gradient demo

import math

AMPLITUDE      = 100  # amplitude of sine wave (can be changed)
UNITS_PER_TURN = 256  # number of angle units in full turn
UNIT_COUNT     = 64   # number of angle units in table

sines = [round(math.sin(i / UNITS_PER_TURN * math.tau) * AMPLITUDE) for i in range(UNIT_COUNT)]
deltas = [s1 - s0 for (s0, s1) in zip([sines[0]] + sines[:-1], sines)]
assert min(deltas) >= 0
assert max(deltas) <= 3
for i in range(UNIT_COUNT - 4, -4, -4):
    print(f"db {deltas[i]}<<6 | {deltas[i+1]}<<4 | {deltas[i+2]}<<2 | {deltas[i+3]}")

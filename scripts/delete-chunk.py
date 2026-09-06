#!/usr/bin/env python3
"""Force a single chunk to regenerate by clearing its entry in the Anvil
region file header. Does NOT touch any other chunk in the region file -
this just zeroes the 4-byte location + 4-byte timestamp entries for the
target chunk, so the next chunk load sees it as never-generated.

DESTRUCTIVE: wipes all blocks/entities/tile-entities in that chunk. Take a
world backup first. Run with the server stopped - editing a region file
the server has open risks corrupting it.
"""
import argparse
import os


def clear_chunk(region_dir, cx, cz):
    rx, rz = cx >> 5, cz >> 5
    lx, lz = cx & 31, cz & 31
    idx = lx + lz * 32

    path = os.path.join(region_dir, f"r.{rx}.{rz}.mca")
    if not os.path.exists(path):
        raise FileNotFoundError(f"no region file at {path} (chunk was never generated)")

    with open(path, "r+b") as f:
        f.seek(idx * 4)
        f.write(b"\x00\x00\x00\x00")
        f.seek(4096 + idx * 4)
        f.write(b"\x00\x00\x00\x00")

    return path


def main():
    parser = argparse.ArgumentParser(description="Clear a chunk from an Anvil region file so it regenerates")
    parser.add_argument("--region-dir", default="/srv/minecraft/liminalindustries/world/region", help="dimension's region/ dir (overworld default; use world/DIM-1/region for the nether, world/DIM1/region for the end)")
    parser.add_argument("chunk_x", type=int)
    parser.add_argument("chunk_z", type=int)
    args = parser.parse_args()

    path = clear_chunk(args.region_dir, args.chunk_x, args.chunk_z)
    print(f"cleared chunk ({args.chunk_x}, {args.chunk_z}) in {path} - it will regenerate on next load")


if __name__ == "__main__":
    main()

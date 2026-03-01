#!/usr/bin/env python3
"""
Converts per-green QGIS exports into a unified local-meter JSON file for the iOS app.

Reads:
  - GeoTIFF raster (clipped DSM, ITM / EPSG:2157)
  - GeoJSON perimeter (WGS84 / EPSG:4326)

The raster is already clipped to the green in QGIS, so its valid-data boundary
defines the mesh extent. The GeoJSON perimeter is used for smooth cake-side walls
and is converted to the same local coordinate system.

Usage:
    python prepare_green.py --hole 1 \
        --tif  ../docs/qgis-export/greens/1/1-green.tif \
        --geojson ../docs/qgis-export/greens/1/1-green.geojson \
        --out ../CourseData/H01_green_data.json

Also supports XYZ input (legacy):
    python prepare_green.py --hole 1 \
        --xyz ../CourseData/H01_green.xyz.txt \
        --geojson ../CourseData/H01_green.geojson \
        --out ../CourseData/H01_green_data.json

Requires: rasterio, pyproj, numpy  (pip install rasterio pyproj numpy)
"""

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from pyproj import Transformer


NODATA_OUT = -9999


def load_geotiff(path: Path):
    """Load clipped GeoTIFF. Returns (data_2d, transform, nodata, crs)."""
    import rasterio
    with rasterio.open(path) as ds:
        data = ds.read(1)
        return data, ds.transform, ds.nodata, ds.crs, ds.width, ds.height


def load_xyz(path: Path):
    """Legacy: Load space-delimited XYZ file. Returns (xs, ys, zs) as 1-D arrays."""
    xs, ys, zs = [], [], []
    with open(path) as f:
        for line in f:
            parts = line.split()
            if len(parts) != 3:
                continue
            xs.append(float(parts[0]))
            ys.append(float(parts[1]))
            zs.append(float(parts[2]))
    return np.array(xs), np.array(ys), np.array(zs)


def load_geojson_perimeter(path: Path):
    """Load perimeter polygon from GeoJSON. Returns list of (lon, lat) tuples.
    Supports Polygon and MultiPolygon geometry types."""
    with open(path) as f:
        data = json.load(f)
    geom = data["features"][0]["geometry"]
    geo_type = geom["type"]
    coords_raw = geom["coordinates"]
    if geo_type == "Polygon":
        ring = coords_raw[0]
    elif geo_type == "MultiPolygon":
        ring = coords_raw[0][0]  # first polygon, first (exterior) ring
    else:
        raise ValueError(f"Unsupported geometry type: {geo_type}")
    return [(c[0], c[1]) for c in ring]


def process_geotiff(tif_path, geojson_path, hole, out_path):
    """Process from GeoTIFF (preferred method)."""
    print(f"Loading GeoTIFF from {tif_path}...")
    data, transform, nodata_val, crs, width, height = load_geotiff(Path(tif_path))
    print(f"  Grid: {width} cols x {height} rows")
    print(f"  CRS: {crs}")

    valid_mask = data != nodata_val if nodata_val is not None else np.ones_like(data, dtype=bool)
    valid_data = data[valid_mask]
    print(f"  Valid pixels: {len(valid_data)} ({len(valid_data)/data.size*100:.1f}%)")

    cell_size = abs(transform.a)
    print(f"  Cell size: {cell_size}m")

    # Use the geometric center of the raster bounding box as origin.
    # Using centroid-of-valid-pixels would shift the origin asymmetrically
    # and misalign the perimeter polygon (which is also zero-based to this origin).
    origin_x = transform.c + (width / 2.0) * transform.a
    origin_y = transform.f + (height / 2.0) * transform.e

    min_z = float(valid_data.min())
    max_z = float(valid_data.max())
    print(f"  Origin (ITM): ({origin_x:.2f}, {origin_y:.2f})")
    print(f"  Elevation range: {min_z:.4f} - {max_z:.4f}m (range {max_z - min_z:.4f}m)")

    # Build height grid in local meters (zero-based elevation)
    grid_origin_x = transform.c - origin_x  # top-left corner X in local
    grid_origin_y = transform.f - origin_y  # top-left corner Y in local

    heights = []
    for r in range(height):
        row = []
        for c in range(width):
            v = float(data[r, c])
            if nodata_val is not None and v == nodata_val:
                row.append(NODATA_OUT)
            elif v > 0 and v < 200:
                row.append(round(v - min_z, 6))
            else:
                row.append(NODATA_OUT)
        heights.append(row)

    # Convert perimeter from WGS84 to ITM to local meters
    print(f"\nLoading GeoJSON from {geojson_path}...")
    perimeter_lonlat = load_geojson_perimeter(Path(geojson_path))
    print(f"  {len(perimeter_lonlat)} perimeter vertices")

    transformer = Transformer.from_crs("EPSG:4326", "EPSG:2157", always_xy=True)
    perimeter_local = []
    for lon, lat in perimeter_lonlat:
        itm_x, itm_y = transformer.transform(lon, lat)
        local_x = itm_x - origin_x
        local_y = itm_y - origin_y
        perimeter_local.append({"x": round(local_x, 4), "y": round(local_y, 4)})

    if perimeter_local[0] != perimeter_local[-1]:
        perimeter_local.append(perimeter_local[0])

    # Clamp perimeter to grid extent so cake sides don't extend beyond the mesh
    x_min = grid_origin_x
    x_max = grid_origin_x + (width - 1) * cell_size
    y_max = grid_origin_y
    y_min = grid_origin_y - (height - 1) * cell_size
    for pt in perimeter_local:
        pt["x"] = round(max(x_min, min(x_max, pt["x"])), 4)
        pt["y"] = round(max(y_min, min(y_max, pt["y"])), 4)

    print(f"  Perimeter: {len(perimeter_local)} vertices (in local meters, clamped to grid)")

    # Grid origin (col=0, row=0) in raster CRS -> reproject to WGS84
    transformer_itm_to_wgs = Transformer.from_crs("EPSG:2157", "EPSG:4326", always_xy=True)
    origin_lon, origin_lat = transformer_itm_to_wgs.transform(transform.c, transform.f)

    output = {
        "hole": hole,
        "grid": {
            "cols": width,
            "rows": height,
            "cellSize": round(cell_size, 4),
            "originX": round(grid_origin_x, 4),
            "originY": round(grid_origin_y, 4),
            "originLat": round(origin_lat, 8),
            "originLng": round(origin_lon, 8),
            "nodata": NODATA_OUT,
            "heights": heights,
        },
        "perimeter": perimeter_local,
        "elevation": {
            "minRaw": round(min_z, 4),
            "maxRaw": round(max_z, 4),
            "range": round(max_z - min_z, 4),
        },
    }

    out = Path(out_path)
    with open(out, "w") as f:
        json.dump(output, f)

    size_kb = out.stat().st_size / 1024
    print(f"\nWrote {out} ({size_kb:.0f} KB)")
    print("Done.")


def process_xyz(xyz_path, geojson_path, hole, out_path):
    """Legacy: Process from XYZ file."""
    print(f"Loading XYZ from {xyz_path}...")
    xs, ys, zs = load_xyz(Path(xyz_path))
    print(f"  {len(xs)} points loaded")

    print(f"Loading GeoJSON from {geojson_path}...")
    perimeter_lonlat = load_geojson_perimeter(Path(geojson_path))
    print(f"  {len(perimeter_lonlat)} perimeter vertices")

    valid_mask = (zs > 0) & (zs < 200)
    valid_zs = zs[valid_mask]
    valid_xs = xs[valid_mask]
    valid_ys = ys[valid_mask]
    print(f"  {valid_mask.sum()} valid height points")

    unique_x = np.sort(np.unique(xs))
    unique_y = np.sort(np.unique(ys))[::-1]
    cols = len(unique_x)
    rows = len(unique_y)
    cell_size = round(float(unique_x[1] - unique_x[0]), 4) if len(unique_x) > 1 else 0.25

    origin_x = float(np.mean(valid_xs))
    origin_y = float(np.mean(valid_ys))
    min_z = float(valid_zs.min())
    max_z = float(valid_zs.max())

    x_to_col = {x: i for i, x in enumerate(unique_x)}
    y_to_row = {y: i for i, y in enumerate(unique_y)}

    heights = [[NODATA_OUT] * cols for _ in range(rows)]
    for x, y, z in zip(xs, ys, zs):
        c = x_to_col.get(x)
        r = y_to_row.get(y)
        if c is not None and r is not None:
            if z > 0 and z < 200:
                heights[r][c] = round(z - min_z, 6)
            else:
                heights[r][c] = NODATA_OUT

    grid_origin_x = float(unique_x[0] - origin_x)
    grid_origin_y = float(unique_y[0] - origin_y)

    transformer = Transformer.from_crs("EPSG:4326", "EPSG:2157", always_xy=True)
    perimeter_local = []
    for lon, lat in perimeter_lonlat:
        itm_x, itm_y = transformer.transform(lon, lat)
        local_x = itm_x - origin_x
        local_y = itm_y - origin_y
        perimeter_local.append({"x": round(local_x, 4), "y": round(local_y, 4)})

    if perimeter_local[0] != perimeter_local[-1]:
        perimeter_local.append(perimeter_local[0])

    output = {
        "hole": hole,
        "grid": {
            "cols": cols, "rows": rows,
            "cellSize": cell_size,
            "originX": round(grid_origin_x, 4),
            "originY": round(grid_origin_y, 4),
            "nodata": NODATA_OUT,
            "heights": heights,
        },
        "perimeter": perimeter_local,
        "elevation": {
            "minRaw": round(min_z, 4),
            "maxRaw": round(max_z, 4),
            "range": round(max_z - min_z, 4),
        },
    }

    out = Path(out_path)
    with open(out, "w") as f:
        json.dump(output, f)

    size_kb = out.stat().st_size / 1024
    print(f"\nWrote {out} ({size_kb:.0f} KB)")


def main():
    parser = argparse.ArgumentParser(description="Prepare green data for iOS app")
    parser.add_argument("--hole", type=int, required=True)
    parser.add_argument("--tif", type=str, help="Path to clipped GeoTIFF (preferred)")
    parser.add_argument("--xyz", type=str, help="Path to .xyz.txt (legacy)")
    parser.add_argument("--geojson", type=str, required=True, help="Path to .geojson (WGS84)")
    parser.add_argument("--out", type=str, required=True, help="Output JSON path")
    args = parser.parse_args()

    if args.tif:
        process_geotiff(args.tif, args.geojson, args.hole, args.out)
    elif args.xyz:
        process_xyz(args.xyz, args.geojson, args.hole, args.out)
    else:
        print("Error: provide either --tif or --xyz", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

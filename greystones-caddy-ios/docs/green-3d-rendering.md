# Green 3D Rendering Pipeline

## Overview

The app renders an interactive 3D visualization of each golf green using SceneKit. The surface shows a heatmap (blue = low, red = high) with slope arrows indicating the direction a ball would roll. Users can adjust vertical exaggeration and rotate/zoom the view.

## Data Pipeline

Raw data comes from two QGIS exports per green:

- **XYZ raster** (`H01_green.xyz.txt`) -- Bluesky LiDAR elevation data in Irish Transverse Mercator (EPSG:2157). ~0.25m cell spacing, ~12K points per green with NoData (-32767) outside the clipped boundary.
- **GeoJSON perimeter** (`H01_green.geojson`) -- Smooth vector polygon traced in Google Earth, exported as WGS84 (EPSG:4326).

These two files use different coordinate systems, so a Python pre-processing step converts both into a single unified JSON file in local meters.

### Pre-processing

```
tools/prepare_green.py
```

Requires `pyproj` and `numpy` (`pip install pyproj numpy`).

Usage:
```bash
python tools/prepare_green.py \
  --hole 1 \
  --xyz CourseData/H01_green.xyz.txt \
  --geojson CourseData/H01_green.geojson \
  --out GreystonesCaddy/GreystonesCaddy/H01_green_data.json
```

What it does:
1. Loads XYZ grid (ITM easting/northing/elevation)
2. Loads GeoJSON perimeter (WGS84 lon/lat)
3. Converts perimeter from WGS84 to ITM via `pyproj`
4. Computes the centroid of valid data as the local origin (0, 0)
5. Normalizes both grid and perimeter to local meters from that origin
6. Zero-bases elevations (subtracts minimum valid elevation)
7. Writes a single JSON file with grid + perimeter in the same coordinate space

### Output format

`H01_green_data.json`:

| Field | Description |
|---|---|
| `hole` | Hole number |
| `grid.cols`, `grid.rows` | Grid dimensions (e.g. 122 x 104) |
| `grid.cellSize` | Cell spacing in meters (0.25) |
| `grid.originX`, `grid.originY` | Grid top-left corner in local meters |
| `grid.nodata` | Sentinel value for invalid cells (-9999) |
| `grid.heights` | 2D array [row][col] of zero-based heights in meters |
| `perimeter` | Array of {x, y} points in local meters (same origin as grid) |
| `elevation.minRaw`, `elevation.maxRaw`, `elevation.range` | Original elevation stats in meters ASL |

## App Architecture

### Files

| File | Role |
|---|---|
| `GreenTerrainData.swift` | Data model and JSON loader |
| `Green3DView.swift` | SceneKit rendering (mesh, heatmap, cake sides, arrows) |

### GreenTerrainData

Loads `HNN_green_data.json` from the app bundle. Provides:
- Grid access: `worldX(col:)`, `worldZ(row:)`, `isValid(row:col:)`, `height(row:col:)`
- Bilinear interpolation: `interpolatedHeight(atX:z:)` for sampling at arbitrary positions
- Smoothing: `smoothedHeights(radius:)` for Gaussian-blurred grid (used by slope arrows)

### Rendering Pipeline

**Grid Mesh** -- Iterates the full height grid. For each cell where all 4 corners are valid, emits 2 triangles (CCW winding). Invalid/NoData cells are skipped, giving the natural green boundary from the QGIS raster clip. At 0.25m cell size, the boundary staircase is imperceptible. Per-vertex normals are computed from central differences on the height field.

**Heatmap Texture** -- A UIImage rendered at grid resolution (122 x 104 pixels). Each valid cell is colored on the blue-to-red spectrum based on its normalized height. NoData cells are left transparent. UV coordinates map directly from grid position, with V flipped for SceneKit's bottom-left texture origin.

**Cake Sides** -- The smooth GeoJSON perimeter polygon defines the vertical walls. For each edge, the top height is sampled from the grid via bilinear interpolation. The bottom sits at a fixed offset below the surface. Brown earth-tone PBR material.

**Slope Arrows** -- Sampled every 8 cells (~2m). The grid is Gaussian-smoothed (radius 3) before gradient computation to capture macro breaks and ignore LiDAR noise. Arrows are oriented in the steepest-descent direction (negative gradient). Rendered as textured planes with constant lighting.

## Adding a New Hole

1. In QGIS, clip the Bluesky DSM raster to the green's polygon boundary:
   - Use "Clip raster by mask layer" (GDAL)
   - Set NoData to -32767
   - Export clipped raster as XYZ: `HNN_green.xyz.txt`
   - Export polygon as GeoJSON (CRS84/WGS84): `HNN_green.geojson`

2. Run the pre-processing script:
   ```bash
   python tools/prepare_green.py \
     --hole N \
     --xyz CourseData/HNN_green.xyz.txt \
     --geojson CourseData/HNN_green.geojson \
     --out GreystonesCaddy/GreystonesCaddy/HNN_green_data.json
   ```

3. The JSON file is automatically picked up by Xcode (file-system-synchronized group). Build and run.

## Previous Issues (Resolved)

- **No interior mesh vertices**: The old renderer only triangulated the ~50 perimeter boundary points. The green surface was a flat polygon with no contour detail.
- **Coordinate system mismatch**: XYZ data was in ITM (EPSG:2157) but the elevation interpolation assumed WGS84 lat/lon with 3m spacing. Every height sample was wrong.
- **Heatmap UV misalignment**: The texture was generated from the full grid but UV coords were mapped to perimeter vertices only.
- **SceneKit blank screen**: Caused by oversized coordinates (raw ITM values in the hundreds of thousands) exceeding floating-point precision in the scene graph.

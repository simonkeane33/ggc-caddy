# 3D Green Pipeline Guide

**The authoritative version of this guide lives in the mission-control-vault.**

## Where to Find the Full Guide

- **Vault path:** `mission-control-vault/02-Projects/Personal/iOS Caddy App/assets/documentation/04-implementation/help/3D-Green-Pipeline-Guide.md`
- **Obsidian link:** `[[04-implementation/help/3D-Green-Pipeline-Guide]]` (when the vault is open)

The vault holds the complete step-by-step workflow from KML import to JSON in Xcode; QGIS stages; CRS; naming; validation; troubleshooting.

## Developer-Local Context

- **Repo tools:** `tools/prepare_green.py` — run with `--hole`, `--tif`, `--geojson`, `--out`
- **App loader:** `GreenTerrainData.load(hole:)` expects `H{02d}_green_data.json` in the bundle
- **Related repo doc:** `docs/green-3d-rendering.md` — app architecture, rendering pipeline

Do not maintain a duplicate full version here. The vault is the authoritative home for this operational scaling workflow.

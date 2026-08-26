# Landform Generation Redesign

## Status

This spec supersedes the goal, generation-domain, base-terrain, drainage, and ocean sections of `2026-08-23-river-generation-redesign.md`. Its river mesh and crop-selection rules remain valid.

## Implemented Baseline

As of 2026-08-25, the generated world uses default seed 149, sea level -2 metres, and global relief 200 metres. The playable area is a 256 by 256 metre crop of the fixed 2048 by 2048 metre generation domain. Visible terrain uses 0.5 metre samples, hydrology uses 4 metre cells, and the full-domain preview uses 2 metre terrain samples.

The Inspector exposes crop offsets on the world X and Z axes in 4 metre steps. These offsets select a different part of the same generated domain while the playable terrain remains centered on the local origin. The full-domain preview moves the crop outline to show the selected source area.

River dimensions use an unclamped flow profile. Effective flow is accumulated drainage area multiplied by the discharge scale. The defaults are:

- Minimum visible flow: 16384.
- Reference flow: 65536.
- Discharge scale: 2.0.
- Reference width: 3.0 metres with exponent 0.45.
- Reference depth: 0.8 metres with exponent 0.35.
- Bank falloff: four times the calculated depth.
- Maximum centerline correction: 2.0 metres.

Width, depth, and bank falloff have no hard geometry limits. Tributaries keep their incoming flow profile at confluences. Water remains a static visual surface without swimming, buoyancy, or flow physics. The full automated suite passes 74 tests at this baseline.

## Goal

Generate a deterministic 256 by 256 metre playable landscape with broad elevation changes, mountains, drainage valleys, rivers, and possible ocean coastlines. Default seed 149 contains a river suitable for the bridge-building demo. A coastline is optional for that seed.

Generation must use the seed and absolute world coordinates. Increasing the visible area must reveal more terrain without changing existing height, land, or ocean samples.

## Generation Domain

Generate visible terrain at 0.5 metres per sample over `[-128, 128)` on both horizontal axes. Analyze hydrology at four metres per sample with 896 metres of padding on each side. The hydrology domain is therefore 512 by 512 samples over `[-1024, 1024)`.

The editor full-domain preview renders this complete 2048 by 2048 metre domain at two metres per terrain sample. Runtime generation renders the playable crop at 0.5 metres per sample.

## Base Landforms

Build the initial height at each absolute world coordinate from scale-separated deterministic fields:

1. A low-frequency continental field defines stable ocean and land areas relative to a fixed sea level.
2. A low-frequency macro-elevation field creates broad rising and falling land.
3. Ridged, domain-warped noise creates mountain groups. Fade mountains near the coast and outside highland areas.
4. Existing hill and ground-detail scales provide local relief.

Keep transitions continuous near the coast. Do not classify ocean by connectivity to the current generation boundary. Closed low areas can appear as inland seas; distinct lake and ocean simulation remains out of scope.

## Valleys and Rivers

Run drainage once on the initial four-metre height field. Fade in broad valley erosion before the visible river-channel threshold, then increase its strength and width gradually with drainage area. Do not raise terrain.

Recalculate depression filling, drainage, and accumulation once after valley erosion. Build the canonical river network from this second pass, then crop it using the existing end-to-end selection rules. River carving remains a separate, narrower pass that uses the final shared channel profile.

Ocean water uses the fixed sea level and covers final terrain below that level, including submerged river mouths. River water keeps its downstream-varying profile and overlaps the ocean at its mouth.

Visible drainage begins when effective flow reaches 16384. Effective flow is accumulated drainage area multiplied by the discharge scale. Width, depth, and valley erosion grow continuously from almost zero toward the reference river profile at an effective flow of 65536. Do not apply a separate distance-based source taper or hard width and depth limits.

## Placement

Scale tree count with the 256 by 256 metre playable area. Reject trees below sea level, inside water corridors, on steep slopes, near the player, near map edges, or too close to another tree.

Find a deterministic dry-land player spawn near a visible river. The default seed must satisfy this requirement.

## Verification

Automated tests must prove:

- The visible and full-domain dimensions are correct.
- Existing coordinate samples remain identical when the output extent changes.
- The same seed repeats terrain, ocean classification, rivers, and trees.
- The default seed has broad relief, mountain-scale elevation, a bridgeable crossing river, and dry player ground.
- Valley erosion only lowers land and is strongest along high-flow drainage paths.
- Ocean classification does not depend on the generated crop boundary.
- Trees remain on dry, suitable land.

Use an editor preview and an interactive playtest to judge landform composition, coastline shape, traversal, and whether the river remains useful for the bridge demo.

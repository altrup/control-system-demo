# River Generation Redesign

## Status

This spec supersedes the terrain-generation and water sections of `2026-08-23-generated-world-design.md`. The player, input, and tree-scene decisions in that document remain valid.

## Goal

Generate a deterministic 128 by 128 metre forest arena from a fixed seed. A suitable seed can contain a shallow stream that enters and leaves the visible world. Terrain carving and the water surface must come from the same river network, so every visible channel contains water and water stays inside its banks.

The user selects the seed through the existing editor preview. The generator does not force a river, search for a crop, or select the globally largest channel. A seed without a valid crossing stream produces a riverless arena.

## Generation Domain

Generate the visible terrain at one metre per sample over `[-64, 64)` on both horizontal axes. Analyze hydrology with 128 metres of padding on each side. The hydrology domain is therefore 384 by 384 samples over `[-192, 192)`.

The padding supplies upstream drainage before a stream enters the visible world. Only the central 128 by 128 samples are sent to Terrain3D. Store them as four 64 metre regions because Terrain3D aligns regions to the world origin. Changing the visual world size must not change base-terrain samples at existing world coordinates.

Generation remains synchronous and happens once per seed. Measure generation time on the current machine. The initial target is at most five seconds for an editor preview. Optimize the hydrology pass if it exceeds that target; do not reduce padding without a separate design decision.

## Hydrology and Channel Selection

Create drainage data from a copy of the base height field. Depression filling can change this routing copy, but it must never directly change visible terrain.

Calculate one downstream neighbor and accumulated upstream area for each hydrology cell. Cells above a fixed drainage-area threshold form a directed channel graph. The threshold uses square metres of upstream area, so it does not depend on the visible map dimensions. The graph can remain grid-based, but its cell centers are not render geometry.

Keep a channel component only when it has an upstream crossing into the visible world and a downstream crossing out of it. Retain all components that pass; do not rank them by global size. Do not render a branch whose first above-threshold point is inside the visible world. Interior springs, ponds, wetlands, lakes, and seasonal channels remain out of scope.

Reject a component if maintaining its downstream grade requires lowering the water surface more than 2.0 metres below the local drainage surface. Intended channel depth does not count toward this grade-correction limit. This prevents a filled routing surface from creating an artificial canyon without limiting the designed river depth. If no component remains, the seed has no visible river.

## Shared Channel Profile

Convert each retained graph path into a terrain-constrained spline. Add deterministic sub-cell bends to remove long cardinal and diagonal runs, limit displacement to less than one terrain cell, and preserve every confluence and boundary endpoint. Resample the spline at intervals of at most 0.5 metres. The resampled points are the only channel geometry consumed downstream.

Each point stores:

- World position and downstream direction.
- Accumulated upstream area.
- Water-surface height.
- Water half-width.
- Water depth.
- Bank falloff width.

Width and depth increase gradually with accumulated flow. They can increase at a confluence and must not saturate near their maximum immediately after the visibility threshold. Smooth adjacent values along the branch to remove one-cell changes.

The water surface is level across each channel section and never rises downstream. Constrain it below the unchanged terrain at both outer bank edges, leave at least 0.15 metres of dry-bank freeboard, and limit downstream grade changes across shared junctions. The bed is the water surface minus local depth. Terrain carving and mesh generation consume these same channel points.

## Initial Tuning Values

Start channel visibility at 4,096 square metres of accumulated upstream area. Let the drainage ratio equal accumulated area divided by this threshold. Set full water width to `3.0 * drainage_ratio^0.45`, capped at 8.0 metres. Set center depth to `0.8 * drainage_ratio^0.35`, capped at 1.8 metres. Set bank falloff from the local depth, with a range of 2.0 to 4.8 metres.

Expose the threshold, width range, width exponent, depth range, depth exponent, bank falloff range, and maximum centerline cut for hands-on editor tuning. These are scene-selection and feel values, not separate generation modes. The fixed seed and automated behavior tests must remain deterministic for any chosen values.

## Terrain Carving

Start from the unchanged visible base height field. Carve only retained visible channel corridors.

For each sampled section, retain full depth across the central 60 percent of the water half-width. Use the remaining 40 percent as a submerged slope that meets the water surface at the mesh edge, then blend through a smooth dry-bank profile to unchanged terrain. Apply the complete cross-section over several terrain cells. Never lower only the centerline cell.

At confluences, use the union of the incoming and outgoing channel corridors. A terrain cell can be lowered by more than one corridor, but the lowest resulting profile wins. Terrain outside all retained corridors remains bit-for-bit equal to the base height field.

## Water Mesh

Generate a static `ArrayMesh` from the shared channel profile. Each section supplies left-bank, center, and right-bank vertices. Extend the top surface 0.5 metres into the rising dry-bank profile so Terrain3D interpolation and level-of-detail changes cannot expose a crack.

Connect consecutive sections with indexed triangles. Do not add vertical or sloped edge skirts. Join branches with a confluence patch that uses their shared junction height and covers the union of their water edges. Extend each boundary section until its complete water and bank profile is outside the visible world. Clip water triangles at the terrain edge; do not clamp individual vertices. This keeps diagonal river mouths full-width and inside the crop.

The initial material remains a simple transparent water material. Flow animation, foam, refraction, underwater post-processing, buoyancy, and swimming remain separate work after the geometry is accepted.

## World Integration

`world_generator.gd` coordinates base terrain, river generation, trees, and player placement. Keep river responsibilities separate:

- `river_network.gd` owns routing, accumulation, graph selection, and shared channel profiles.
- `river_carver.gd` applies channel profiles to the visible height field.
- `river_mesh_builder.gd` creates water surfaces and confluence patches.
- Remove `river_shoreline.gd` after all callers use the shared profile.

Scale tree count by visible area. Trees and the player must remain outside carved water corridors. When the seed has no visible river, use a deterministic dry-land spawn.

## Verification

Automated tests must prove:

- The same seed produces identical base terrain, channel profiles, carved terrain, and tree positions.
- The visible height field is 128 by 128 and hydrology uses the full 128 metre padding.
- Routing changes do not modify visible base terrain.
- Every rendered component crosses into and out of the visible world.
- No rendered branch starts inside the visible world.
- Greater accumulated flow produces a wider and deeper downstream channel.
- Water height never rises downstream, abrupt grade changes are bounded, the bed stays below water, and both outer banks retain dry freeboard.
- Rendered channels have no grid-aligned corner sharper than 30 degrees and no exact straight run longer than 16 metres.
- Water top geometry has no skirt vertices below the local surface, and its outer edge overlaps rising bank terrain.
- Carving changes a complete corridor and leaves all cells outside it unchanged.
- Every retained branch produces mesh triangles and confluence patches contain no open junction gap.

Run the full GUT suite and `godot --headless --editor --path . --quit`. Measure generation time separately. Finish with an interactive visual check of the editor preview and first-person scene. Accept the result only when water reaches map boundaries, channel widths vary, banks have no one-cell spikes, tributaries join without holes, and no river begins or ends inside the visible world.

## Commit Sequence

1. Expand the deterministic generation and hydrology domains.
2. Extract valid boundary-crossing channel profiles.
3. Carve visible terrain from the shared profiles.
4. Generate branch and confluence water meshes from the profiles.
5. Integrate preview, tree density, spawn behavior, and remove obsolete shoreline code.

Commit each slice with its tests after its narrow checks pass.

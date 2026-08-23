# Generated World Design

## Goal

Build a repeatable first arena from a fixed seed. The arena contains walkable terrain, a shallow stream, a flat water surface, simple trees, and the existing first-person player. Tool use and hand interaction remain out of scope.

## Terrain3D

Use the complete official Terrain3D 1.0.2 stable `addons/terrain_3d` directory. Enable its editor plugin as the GitHub installation instructions require. Do not include the optional demo project because the release demo and a runtime generation probe have already passed with Godot 4.7.1 and Jolt.

Keep all supported platform binaries in the add-on. The dependency is pinned by committing this release to the repository.

## Generation

Generate one 64 by 64 metre Terrain3D region at run time. Keep the region in positive coordinates and place its centre at `(32, 32)` to match Terrain3D region alignment without extra coordinate mapping.

Use a typed `RefCounted` generator for deterministic height samples and tree positions. The world scene owns engine objects and turns the generated data into Terrain3D terrain, water, trees, and the player spawn.

Use `FastNoiseLite` for gentle land variation. Carve a smooth, shallow stream bed along a slightly curved centreline. Keep the banks above the fixed water level and the stream bed below it.

Use one transparent horizontal mesh for water. The terrain hides the mesh outside the stream channel. Water has no flow, buoyancy, swimming, or physics in this slice.

Place simple tree scenes with a seeded random generator. Each tree has a primitive trunk, a primitive canopy, and trunk collision. Tree positions must avoid the stream corridor, player spawn, region edges, and other trees. Trees remain separate scene instances because later cutting needs per-tree state.

Spawn the player on one bank and face the camera toward the stream. Keep the existing movement, mouse look, and hold-Control crouch behavior.

## Terrain3D Runtime Rules

- Wait for scene-tree readiness before accessing `Terrain3D.data`.
- Set `free_editor_textures` to `false` for generated in-memory assets.
- Give Terrain3D the active camera.
- Import generated height data through Terrain3D's stable image import API.

## Verification

Use GUT tests to prove that the same seed produces the same heights and tree positions, the stream bed is below water, the banks are above water, and trees respect exclusion zones and minimum spacing.

Use a world integration test to prove that the scene creates Terrain3D, water, trees, and a valid player spawn. Run the GUT suite and the headless Godot editor check. Finish with a manual interactive playtest for movement, collision, camera behavior, and visual clarity; do not automate desktop input.

## Deferred Scope

Do not add infinite chunks, erosion, biomes, caves, terrain deformation, generated-world saves, swimming, water physics, foliage systems, tools, hands, or destructible trees in this slice.

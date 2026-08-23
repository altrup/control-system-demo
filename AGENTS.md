# Control System Demo

## Purpose

This Godot 4.7.1 GDScript prototype tests whether high-level, human-like intent can make physical building expressive without direct control of hands, arms, or muscles. The player chooses the intended result; the character resolves posture, grip, balance, and body motion.

The working design source is `/media/storage/Altrup/Documents/Research/emergent-survival-game/control-system-demo.md`. Playtest results override design assumptions.

## Demo contract

- Target keyboard and mouse only. Defer controller support until the initial interaction works.
- Let the player mark a straight world-space segment with two ray-picked surface points. Do not wrap or project the segment across a surface.
- For tool use, combine the marked line with the following mouse gesture to determine approach angle and speed.
- Let the player carry full-size timber and place it with a transparent final-pose preview. Direction input must not rescale the timber.
- Use the axe, adze, chisel, mallet, auger, and hands. Add another tool only when these cannot perform a required operation without tedium.
- Use notches and wooden pegs for the first permanent joints. Unsupported or unfastened objects must fall after release.
- Use a small crossing over a shallow stream as the test scene. The player must be free to build any stable crossing.

The demo succeeds when an unbriefed player can:

1. Mark and perform a deliberate cut.
2. Explain how swing angle and speed affect the result.
3. Carry and intentionally place timber.
4. Join pieces into a stable crossing.
5. Complete the test without describing the controls as fiddly.

Do not add survival systems, tool crafting, NPC simulation, a full settlement, netcode, or the full material simulation.

## Godot practices

- Use typed GDScript consistently. Use GDScript only unless profiling proves that it cannot meet a measured requirement.
- Follow Godot naming: `snake_case` files, folders, functions, variables, and signals; `PascalCase` classes and node names; `CONSTANT_CASE` constants. Name signals for events that happened.
- Define gameplay inputs as semantic Input Map actions. Do not bind gameplay logic directly to physical keys. Raw mouse position, motion, and button data are valid gesture inputs.
- Read discrete input in `_unhandled_input()` when appropriate. Perform physics queries, movement, and physics-owned transform changes in `_physics_process()`.
- Keep scenes self-contained. The owning parent supplies external dependencies, calls owned children directly, and uses signals for events that must travel upward or across scene boundaries.
- Do not add an autoload until a system has isolated state that must remain globally available across scenes.
- Use a `Node` only when code needs scene-tree lifecycle, transforms, or engine services. Use `RefCounted` for pure calculations and `Resource` for shared or Inspector-edited serialized data.
- Keep assets near the scene that owns them. Add directories only when files need them.
- Expose values that need hands-on feel tuning with `@export`. Do not generalize values that are not being tuned.
- Do not add an add-on, framework, global event bus, or custom architecture before a demonstrated need.
- Track source assets and their `.import` and `.uid` metadata. Never track `.godot/` cache data.

## Verification

- Use TDD for pure calculations and other behavior that can fail without visual judgment.
- Use manual playtests for control feel, visual clarity, and the five success criteria. Automated checks do not replace these playtests.
- Run the narrowest relevant automated check, then run `godot --headless --editor --path . --quit` and inspect its output for script, resource, or import errors.
- Run the changed scene interactively for changes to input, physics, camera behavior, placement, or feedback.

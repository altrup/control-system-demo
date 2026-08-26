# Axe Control Design

## Goal

Test whether a player can mark and perform a deliberate axe cut through high-level physical control. The player selects the intended cut line, and the character resolves stance, reach, grip, and tool orientation. Mouse motion controls the axe-head target and determines the resulting swing path and speed.

This slice ends at repeated visible cuts. It does not fell trees or remove mesh geometry.

## Interaction Flow

Keep the mouse captured and use the centre crosshair for line selection. The first left-click ray-picks point A on a cuttable object. While point A is active, show a live straight segment from point A to the current ray hit. The second left-click selects point B on the same cuttable object and fixes one straight world-space segment. Limit both picks to an exported maximum raycast distance.

After point B, disable manual movement and move the character automatically to a suitable stance within the axe working-distance range. The stance is a preferred area, not an exact line alignment. Record the player's horizontal view-right direction when the line is completed. Calculate the horizontal outward direction from the line midpoint to the player's marking position. Project the marked line onto the horizontal plane and select the end that points toward the recorded view-right direction. Use the recorded view-right direction instead when the projection is too short to give a stable direction. Use this direction for right-handed mode and its opposite for left-handed mode. Normalise the sum of the outward and handed-side directions to get the preferred stance direction. Place the stance at the middle of the working-distance range along that direction. This puts the player in the appropriate front-side area and usually foreshortens the marked line without requiring it to appear as an exact point.

Use the existing collision-aware character movement to reach the stance and turn the camera and movement frame toward the line midpoint. Do not teleport the player. If the distance to the stance does not decrease for one second, cancel the interaction and restore normal control. The short selection range makes this an adjustment of a few steps rather than a navigation task.

Start axe control when the character reaches the stance. Right-click or Escape cancels point A, a completed line, automatic positioning, or axe control. Cancellation removes the line, returns the axe to its held pose, and restores normal camera and movement control. While an interaction is active, Escape performs cancellation before it can release the captured mouse. Do not add tool switching.

## Handedness

Expose right-handed and left-handed modes as an Inspector-edited player setting, with right-handed as the default. Handedness mirrors the preferred automatic stance, axe control anchor, and held pose. Do not add a settings screen or a run-time handedness toggle in this slice.

## Marked Segment and Tool Geometry

Store the selected segment as two world-space points and its owning cuttable object. The segment is independent of the axe mesh and does not wrap or project across the surface.

Define the axe's controlled geometry with scene markers: a grip or control anchor and two endpoints for the working blade edge. The controller operates on this marked working edge, not on hard-coded axe mesh dimensions. Keep the initial implementation specific to the axe; do not add a tool base class or framework before a second tool proves a shared interface is useful.

The desired axe orientation keeps the working edge parallel to the marked segment. Its blade faces from the actual working-edge midpoint toward the marked-line midpoint. Calculate desired orientation from the axe's actual position, not the mouse target. Translational and rotational errors can therefore differ: the axe can lag in position while still facing the line accurately.

## Reach and Mouse Mapping

Constrain the virtual axe target to a player-centred forward hemisphere. Mouse movement maps directly in current screen direction: moving right moves the target right across the hemisphere, and moving up moves it up. Initialise the virtual target from the axe's current working-edge position when axe control starts so that control activation does not pull the axe suddenly.

The hemisphere radius represents the posture and reach that the character resolves automatically. Let W/S change the player's distance from the marked-line midpoint within exported minimum and maximum working distances. The hemisphere expands or contracts over this narrow range so that the marked line remains reachable. At either distance boundary, discard only the blocked radial movement component; preserve tangential movement. A/D moves the player around the target. The camera and movement frame continue to face the interaction target.

During axe control, aim the camera at the midpoint between the actual working-edge midpoint and the marked-line midpoint. The camera follows the actual axe, not the virtual target, so the player can see inertia and contact. Mouse motion controls only the virtual axe target in this state.

## Physical Control

Treat the virtual target as a spring-and-damper controller. Position error produces force toward the virtual working-edge position. Orientation error produces torque toward the desired blade orientation. Damping opposes relative linear and angular velocity so the tool settles without removing inertia. Cap force and torque with exported character-strength limits.

Use persistent linear and angular velocity. A quick mouse stop or reversal does not stop the axe immediately; the tool can overshoot while force and torque reverse its motion. High stiffness should make ordinary free movement feel direct, but mathematically exact mouse tracking is not required.

Keep translational and rotational control independent. A large position error can saturate force while a small orientation error remains within the available torque, and the reverse can also occur.

## Impact, Sticking, and Extraction

Detect collision through the axe's actual swept working edge. A valid impact requires an inward blade velocity above an exported minimum. Stop and embed the axe at the actual contact pose. Keep the marked line active so the player can repeat strikes without marking it again.

Continue applying the same spring-and-damper control while the axe is embedded. Moving the virtual target away from the surface increases outward force as separation grows. Release the axe when the outward force exceeds an exported holding-force threshold. Do not add a separate extraction button or special mouse gesture.

## Visible Cuts

Place each cut at the actual blade contact segment rather than at the marked target segment. Calculate the visible cut contribution from the inward component of actual blade speed and the alignment between the actual working edge and the marked line. Faster, better-aligned strikes create a stronger cut. Slow taps and glancing strikes create little or no cut.

Add a blade-aligned surface mark for each valid strike. Overlapping strikes visually accumulate through additional or strengthened marks. Preserve the cuts while the tree instance exists. Keep the tree collision and trunk geometry unchanged. Do not add mesh subtraction, timber separation, tree health, or felling in this slice.

## Ownership

The player scene owns line-selection state, automatic stance movement, camera behaviour, handedness, and the held axe. The player calls its owned axe controller directly. The axe scene owns its mesh, collision, control markers, physical state, spring-and-damper response, and embedded contact pose. The tree scene owns cuttable collision, holding strength, and visible cut marks. Use direct calls within these ownership boundaries and signals only for events that must travel upward.

Do not add an autoload, global event bus, tool framework, inventory, hand animation, inverse kinematics, or material-simulation system.

## Failure and Cancellation Rules

- Ignore a first click that does not hit a cuttable object within maximum selection range.
- Keep point A active when the live second point is not on the same cuttable object.
- Cancel automatic stance movement if the character makes no progress for one second.
- Cancel the interaction if the selected object leaves the scene.
- Let physics collision and the reach constraint prevent invalid axe motion; do not move the tree or player through geometry to preserve the target pose.

## Verification

Use TDD for pure control calculations. Test that handedness mirrors the stance bias, mouse directions map to the corresponding hemisphere directions, reach boundaries remove only blocked radial movement, spring force and torque grow with error and respect their caps, damping opposes velocity, and impact contribution increases with inward speed and marked-line alignment.

Use scene tests to prove that both line points must use the same cuttable object, selection respects the maximum raycast distance, right-click and Escape cancel every interaction state, the axe exposes its grip and working-edge markers, and repeated valid impacts preserve the marked line while adding visible cuts.

Run the narrow GUT tests, the complete GUT suite, and `godot --headless --editor --path . --quit`. Inspect output for script, resource, physics, or import errors. Run the world interactively to test line selection, automatic stance movement, handedness, camera tracking, reach boundaries, free swings, inertia, impact, sticking, extraction, repeated cuts, and cancellation.

The slice succeeds when an unbriefed player can mark a cut, arrive at a usable handed stance without manual positioning, deliberately strike near the line, see that approach and speed change the cut, extract the axe by pulling away, and repeat the strike without describing the controls as fiddly.

## Deferred Scope

Defer tree felling, trunk or timber separation, mesh deformation, full material simulation, damage or health, arm and hand animation, inverse kinematics, inventory, tool switching, run-time handedness settings, other tools, and general tool architecture.

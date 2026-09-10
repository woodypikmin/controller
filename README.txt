Pikmin Controller Stage 5.1
=============================

Focus: hide Controller refresh + add controls.

1. VISUAL HANDOFF COVER
-----------------------
The iOS foreground refresh is still needed to renew Controller's finite
background execution window.

Stage 5.1 hides it visually:

  Pikmin Expedition list
  -> WDA screenshot
  -> screenshot is prepared as Controller's full-screen cover
  -> activate Controller
  -> begin fresh background task immediately
  -> immediately launch Pikmin
  -> remove cover after Controller is background again

There is NO intentional 0.20-second Controller dwell anymore.

The user should see either:
- no visible switch, or
- at worst a very brief frozen Pikmin frame.

Toggle:
  "隱藏 Controller 切換"

Disable it only for debugging.

2. LOOP CONTROLS
----------------
Selectable targets:
  無限
  5
  10
  20
  50

The UI shows:
  completed dispatch count
  selected target
  RUNNING / STOPPED

If a finite target is reached:
  the loop stops automatically
  and does NOT perform an unnecessary final Controller refresh.

STOP remains available and stops at the next safe checkpoint.

The Stage 5.0 dispatch logic itself is otherwise unchanged.

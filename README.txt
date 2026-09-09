
Pikmin Controller iOS - Stage 1
===============================

Goal
----
Prove that a NORMAL sideloaded iPhone app can talk to the WebDriverAgent
already running on the SAME iPhone and issue WDA screenshot/tap/swipe commands.

This is a real iOS app. It is NOT yet standalone:
WDA still has to be started first using the existing SideTap/phone-harness setup.

Why test this first?
--------------------
If iPhone App -> localhost WDA works, the architecture can become:

Pikmin Controller.app
  -> localhost WDA
  -> screenshot
  -> detection/state machine
  -> tap/swipe
  -> Pikmin Bloom

Then Windows is only needed to start WDA. After that we can investigate whether
WDA can be bundled/started on-device as the final step.

Build from Windows with GitHub Actions
--------------------------------------
1. Create a new GitHub repository.
2. Upload all files from this folder preserving directories.
3. GitHub -> Actions -> "Build unsigned iOS IPA" -> Run workflow.
4. When finished, download artifact:
     PikminController-unsigned-ipa
5. Extract it to get:
     PikminController-unsigned.ipa
6. On Windows, use Sideloadly to sign/install the IPA to the iPhone.

First test
----------
1. On Windows, start WDA as you already do:
     cd C:\SideTap
     .\phone-harness.cmd up

   Confirm:
     WDA answering at http://127.0.0.1:8100

2. Leave WDA running.
3. Open Pikmin Controller on the iPhone.
4. Tap:
     1. Check WDA on 127.0.0.1:8100

Success:
  It shows Local WDA = READY.

5. Tap:
     Get iPhone Screenshot Through WDA

Success:
  Current iPhone screenshot appears inside the app.

6. Tap:
     Create Pikmin Session

7. Put a SAFE x/y coordinate, then tap SEND ONE TAP.

Success:
  Another foreground app receives the touch.

If steps 4-7 work, we have proven that the BOT logic can be moved from Windows
into an iPhone app while WDA supplies the automation layer.

Distribution
------------
This source can be built unsigned in GitHub Actions and locally signed with
Sideloadly. It does not require publishing on the App Store.

Do not expect App Store/TestFlight distribution to grant extra automation
permissions. This experiment intentionally targets sideloaded/development use.

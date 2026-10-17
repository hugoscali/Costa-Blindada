Realistic Shoreline Waves
=========================

Real-time shallow-water simulation for Godot 4.7: breaking waves, swash,
foam, and wet sand computed by an actual fluid solver on the GPU, plus a
standalone Gerstner deep-water ocean shader.

Getting started
---------------
1. Download Godot 4.7 stable (or newer) for Windows from godotengine.org.
2. Place the Godot .exe in this folder.
3. Run one of the launchers:
   - launch.bat     close-up beach demo (also: quay wall and dam-break test)
   - island.bat     2 x 2 km archipelago with surf on every coast
   - openocean.bat  deep-water Gerstner ocean, no solver

Or open this folder as a project in the Godot editor. The first start
imports assets and takes a minute or two. The Forward+ renderer is required.

Documentation
-------------
Open docs/index.html for the full manual: demo controls, how the physics
works, tuning every knob, integrating the system into your own project with
code examples, performance guidance, and ideas for extending it.

License
-------
Code and shaders: MIT (LICENSE.txt).
Bundled textures, models, and sky panoramas: CC0 from Poly Haven
(polyhaven.com). Textures under assets/generated were produced by
tools/gen_textures.py and are covered by the MIT license as well.

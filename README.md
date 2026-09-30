# Smart Parking

A MATLAB parking occupancy project that compares a current image with an empty reference and evaluates individually marked parking spaces. It retains the original six-lane demonstration and supports other fixed-camera parking layouts.

## Run

Requires MATLAB R2021a or later. No additional toolboxes are required. Open this folder in MATLAB and run:

```matlab
smartParking
```

Choose **Choose images** to select the current parking image and empty reference, then mark the spaces. **Bundled demo** uses the historical 36-space preset; use it only with images matching that layout. Replacing the images requires a matching layout.

## Use your own images

1. Capture an empty parking area and a current image from exactly the same camera position, with matching framing. Keep lighting as consistent as possible.
2. Choose the current image, then the empty reference. Different dimensions require explicit confirmation before resizing; resizing does not correct camera movement or perspective changes.
3. Mark each individual parking space on the reference. Click two opposite corners of each space, assign its lane number, then add another space or finish. Press Enter while selecting corners to finish. Avoid including driveways and neighboring spaces. Cancel the lane dialog to stop marking.
4. Save the layout if desired. Load that layout only for the same camera framing. Each rectangle corresponds to one space, so capacity follows the layout rather than a hardcoded total.
5. Set thresholds, review the colored overlay and changed-pixel mask, and optionally export the per-space CSV. Green means available; red means occupied. The highest-numbered lane with available spaces is recommended, preserving the old preference.

The pixel difference threshold controls how much a pixel must change (default 0.15 of the grayscale range). The occupied fraction threshold controls how much of a space must change (default 18%). Increase thresholds to reduce sensitivity; decrease them to detect smaller changes. Validate settings using known empty and occupied examples from your own camera.

## What changed

- Portable paths and image pickers replace machine-specific Windows paths.
- Explicit handling of different image dimensions fixes the supplied pair's size mismatch.
- Individual parking regions replace connected-component car counting, which could merge neighboring cars or split one car into multiple detections.
- Deterministic filtering replaces artificial random noise.
- One shared detection function produces consistent lane and overall totals.
- Validated layout and threshold inputs, reusable layouts, labeled overlays, and CSV export.
- A single results window replaces repeated lane figures.

## Files

- `smartParking.m`: interactive image selection, layout marking, and results.
- `analyzeParking.m`: reusable detection function and input validation.
- `testParking.m`: synthetic regression tests.
- `car.jpeg`, `bg.jpeg`: current parking image and empty reference.

## Verification

Run the MATLAB tests with:

```matlab
results = runtests('testParking.m');
assert(all([results.Passed]), 'Some parking tests failed.');
```

Tests cover empty/full scenes, one occupied space, repeatability, lane recommendation, consistent totals, invalid regions, image dimension validation, explicit resizing, and RGB/grayscale input. An automated launch of the installed MATLAB failed with filesystem permission and Qt processor compatibility errors. The MATLAB tests and interactive interface have therefore not been verified in that environment. Run them before submission and manually exercise image selection, rectangle marking, layout save/load, cancel actions, and CSV export.

## Limits

This is a background-comparison prototype, not a trained vehicle detector. It cannot identify vehicle types or reliably distinguish cars from shadows, people, debris, lighting changes, or camera movement. An empty reference is required. Results are estimates and should be checked visually; no accuracy claim has been established on real parking photographs. Overlapping or incorrectly marked spaces can yield misleading results. The bundled images are illustrations with different resolutions; their reference is explicitly resized for the demo. New sites require new layouts and threshold validation.

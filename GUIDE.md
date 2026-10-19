# Smart Parking

A MATLAB application that compares a parking image with an empty reference, estimates occupancy for individually marked spaces, and recommends an available lane.

**MATLAB R2021a+ · No additional toolboxes · Custom layouts · CSV export**

[Quick start](#quick-start) · [How it works](#how-it-works) · [Tests](#tests) · [Limitations](#limitations)

## Sample images

| Empty reference | Current parking image |
| :---: | :---: |
| ![Empty parking lot](bg.jpeg) | ![Parking lot with cars](car.jpeg) |

These are synthetic parking-lot sample images used as input examples, not real camera photographs or detection results. The current pair shows 18 spaces. Use **Choose images** and mark those spaces; the historical **Bundled demo** preset assumes a different 36-space layout.

The approach makes each occupancy decision inspectable: a space is occupied when enough pixels differ from the empty reference. It is useful for exploring background subtraction with a fixed camera and manually defined regions.

## Features

- Select your own current and empty-reference images.
- Mark individual spaces and assign lane numbers.
- Save and reload layouts for the same camera viewpoint.
- View occupied/free overlays and the changed-pixel mask.
- Review per-lane availability and export per-space results to CSV.
- Adjust detection thresholds without changing the source code.

## Quick start

1. Download or clone this repository.
2. Open the project folder as MATLAB’s current folder.
3. Run:

```matlab
smartParking
```

4. Select **Choose images**. Choose `car.jpeg` as the current image and `bg.jpeg` as the empty reference.
5. Choose **Mark spaces**, then click two opposite corners of each parking space and assign a positive lane number. Save the layout to reuse it.
6. Start with thresholds **0.15** and **0.18**, inspect the results, and export a CSV if needed.

For another parking lot, use images captured from the same fixed camera position and framing. A saved layout is specific to that view. Resizing can match dimensions but cannot correct camera movement.

## How it works

```text
Current image + empty reference
              ↓
Grayscale conversion and absolute difference
              ↓
Pixel threshold and 3 × 3 majority filter
              ↓
Changed-pixel fraction inside each marked space
              ↓
Occupied/free classification → lane availability → CSV
```

| Setting | Default | Meaning |
| --- | --- | --- |
| Pixel difference threshold | 0.15 | Minimum grayscale change on a 0–1 scale |
| Occupied fraction threshold | 0.18 | Minimum fraction of changed pixels in a space |

Green boxes indicate estimated availability; red boxes indicate estimated occupancy. The highest-numbered lane with available spaces is recommended. Increase thresholds to reduce sensitivity; decrease them to detect smaller changes. Validate settings against known examples.

## Project structure

| File | Purpose |
| --- | --- |
| `smartParking.m` | Image selection, layout marking, results and export |
| `analyzeParking.m` | Deterministic detection and input validation |
| `testParking.m` | Synthetic regression tests |
| `bg.jpeg` / `car.jpeg` | Empty reference and current sample image |

## Tests

Run in MATLAB:

```matlab
results = runtests('testParking.m');
assert(~isempty(results), 'No tests discovered; inspect testParking.m.');
assert(all([results.Passed]), 'Some parking tests failed.');
```

Tests cover empty/full scenes, individual occupied spaces, repeatability, lane selection, consistent totals, invalid inputs, RGB/grayscale images, resizing, isolated noise and singleton references.

Test functions are named with a `test` prefix so `functiontests` discovers them ([functiontests documentation](https://www.mathworks.com/help/matlab/ref/functiontests.html)), and `testParking` errors if none are found. The supplied image pair also needs a matching layout; the 36-space preset should not be used to validate it.

## Limitations

This is a background-comparison prototype, not a trained vehicle detector. Shadows, lighting changes, people, debris and camera movement can affect results. It requires an empty reference and correctly marked spaces. It does not identify vehicle types, and no real-world accuracy benchmark has been established.

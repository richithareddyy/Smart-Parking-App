# Real-camera evaluation

This folder measures `analyzeParking.m` on real fixed-camera images. It is separate from the synthetic unit tests, which only check that the code behaves as written. The results below do not apply to the synthetic sample images, and the app's default thresholds are unchanged.

## Dataset

[PKLot](https://web.inf.ufpr.br/vri/databases/parking-lot-database/) (Almeida et al., *Expert Systems with Applications* 42(11):4937–4949, 2015), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The images are not included here. The manifest has 12,416 annotated 1280 × 720 frames from three cameras and 693,755 labeled space observations. One image without an annotation file and 25,773 observations without an occupancy label were excluded. One UFPR05 day folder is named `2013-14-16`, which is not a valid date; it is kept as an identifier.

Files in `results/pklot/` derived from PKLot (splits, references, review sample and scores) are adapted from that dataset under the same attribution.

## Manifest format

| File | Contents |
| --- | --- |
| `frames.csv` | Frame, camera, view, day, time, weather, image path |
| `spaces.csv` | View, space, normalized rectangle, lane, pixel area, overlap with neighboring rectangles, original outline |
| `labels.csv` | Frame, space, occupied (0, 1 or missing) |
| `splits.csv` | Camera, day, split (`train`, `validation`, `test` or `setup`) |
| `references.csv` | One empty reference per view |
| `dataset.json` | Source, license, citation, and split and reference rules; the archive checksum in the committed copy was added separately |

A view is one camera position. When the annotated outlines change, the importer starts a new view with its own layout and reference. `readManifest.m` rejects manifests where a day has two splits, a reference comes from a test day or has an occupied space, or a held-out camera has training days.

## Protocol

- **Splits:** UFPR04 and UFPR05 days are split in date order into 60% training, 20% validation and 20% test. No day appears in two splits.
- **Held-out camera:** PUCPR is never used for tuning. Its first 20% of days only supply an empty reference; the rest are test days.
- **References:** per view, up to 60 evenly spaced fully vacant non-test frames are considered, and the one closest in brightness to the median of up to 60 evenly spaced non-test frames is used.
- **Spaces:** the app uses upright rectangles, so each tilted outline becomes its bounding box. "ROI scale" shrinks that box around its center.
- **Baseline:** a running-average background that starts each day from the same reference and blends in pixels within the difference threshold.
- **Tuning:** balanced accuracy on training days only (validation days were a check, and test days were scored in one run), over 8 difference thresholds, 45 occupied fractions, 3 ROI scales and, for the baseline, 4 learning rates.
- **Intervals:** whole camera days are resampled, because frames minutes apart are nearly duplicates.

| Setting | Difference threshold | Occupied fraction | ROI scale | Learning rate |
| --- | :---: | :---: | :---: | :---: |
| Reference default (app defaults) | 0.15 | 0.18 | 1 | – |
| Reference default thresholds, tuned ROI | 0.15 | 0.18 | 0.75 | – |
| Reference tuned | 0.20 | 0.18 | 0.75 | – |
| Adaptive tuned | 0.15 | 0.24 | 0.5 | 0.02 |

## Results

"False free" is the share of occupied spaces reported free. "False occupied" is the share of free spaces reported occupied.

**New days, known cameras** (UFPR04 and UFPR05, 12 camera days, 53,992 observations)

| Setting | Occupied precision / recall | Free precision / recall | False free | False occupied | Balanced accuracy (95% day interval) |
| --- | :---: | :---: | :---: | :---: | :---: |
| Reference default | 0.803 / 0.997 | 0.994 / 0.713 | 0.3% | 28.7% | 0.855 (0.824–0.876) |
| Reference default thresholds, tuned ROI | 0.835 / 0.995 | 0.993 / 0.768 | 0.5% | 23.2% | 0.882 (0.855–0.902) |
| Reference tuned | 0.931 / 0.968 | 0.961 / 0.916 | 3.2% | 8.4% | 0.942 (0.917–0.961) |
| Adaptive tuned | 0.917 / 0.977 | 0.971 / 0.896 | 2.3% | 10.4% | 0.937 (0.894–0.967) |

**Unseen camera** (PUCPR, 29 days, 322,776 observations)

| Setting | Occupied precision / recall | Free precision / recall | False free | False occupied | Balanced accuracy (95% day interval) |
| --- | :---: | :---: | :---: | :---: | :---: |
| Reference default | 0.466 / 0.989 | 0.930 / 0.113 | 1.1% | 88.7% | 0.551 (0.523–0.598) |
| Reference default thresholds, tuned ROI | 0.464 / 0.976 | 0.865 / 0.118 | 2.4% | 88.2% | 0.547 (0.518–0.595) |
| Reference tuned | 0.465 / 0.871 | 0.682 / 0.215 | 12.9% | 78.5% | 0.543 (0.513–0.589) |
| Adaptive tuned | 0.439 / 0.845 | 0.561 / 0.155 | 15.5% | 84.5% | 0.500 (0.471–0.545) |

**Camera moved, setup not redone** (UFPR04 in January with the December reference and layout, 6 days, 24,326 observations)

| Setting | Occupied precision / recall | Free precision / recall | False free | False occupied | Balanced accuracy (95% day interval) |
| --- | :---: | :---: | :---: | :---: | :---: |
| Reference default | 0.459 / 1.000 | 1.000 / 0.014 | 0.0% | 98.6% | 0.507 (0.502–0.511) |
| Reference default thresholds, tuned ROI | 0.465 / 0.994 | 0.888 / 0.043 | 0.6% | 95.7% | 0.518 (0.511–0.525) |
| Reference tuned | 0.532 / 0.893 | 0.793 / 0.343 | 10.7% | 65.7% | 0.618 (0.588–0.632) |
| Adaptive tuned | 0.574 / 0.788 | 0.742 / 0.510 | 21.2% | 49.0% | 0.649 (0.577–0.692) |

Training and validation scores are in `results/pklot/summary.csv`.

- On known cameras, tuning raised balanced accuracy from 0.855 to 0.942, but false-free errors rose from 0.3% to 3.2%. A false free sends a driver to a taken space, so the tuned setting is not simply better.
- The adaptive baseline did not clearly beat the fixed reference; the intervals overlap widely.
- On the unseen camera every setting was close to chance. Thresholds tuned on one lot did not transfer with the available reference.

**Runtime** on an Apple M5 with MATLAB R2026b, 200 test frames: 12.7 ms median (18.6 ms 95th percentile) for the detector, 13.4 ms (16.1 ms) for the adaptive baseline, plus 6.5 ms to read the image.

## Failure analysis

Breakdowns by camera, weather, hour, brightness, estimated image shift, rectangle overlap and space size are in `conditions.csv`; per-space scores are in `per_space.csv`. These are associations, not proof of cause. Scores below are for the tuned fixed reference.

- **Lighting:** PUCPR's fully vacant setup frames were only around 06:00 and 18:00, which led to a hazy dawn reference. Where frame and reference brightness were within 0.05, balanced accuracy was 0.927; where the frame was more than 0.10 brighter (85% of observations) it was 0.507. The background update cannot correct a gap larger than its threshold.
- **Weather:** on known cameras, sunny days were worst (0.909, against 0.956 cloudy and 0.983 rainy).
- **Alignment:** skipping setup after the camera moved dropped the tuned UFPR04 score from 0.931 to 0.618. Estimated shift showed no consistent trend on known cameras. On PUCPR, scores fell from 0.654 at 0 px to 0.502 above 5 px, but larger shifts coincided with brighter frames: among frames more than 0.10 brighter than the reference, scores stayed between 0.491 and 0.513 at every shift (computed from the predictions file, which is not committed).
- **Low contrast:** red and dark cars can match the pavement's gray level.
- **Shadows, occlusion and overlap:** shadows and neighboring cars caused some false-occupied errors. PKLot has no shadow or occlusion labels, so these could not be measured for the full set.

A sample of 80 test errors (10 per setting, group and error type, at most one per camera day) was tagged from image crops. This was a single unblinded pass without a second reviewer, and equal sampling means the counts do not estimate overall shares.

| Group | Error | Tags |
| --- | --- | --- |
| Known cameras | False free (20) | 16 low contrast, 3 region misses car, 1 unclear |
| Known cameras | False occupied (20) | 10 lighting, 5 shadow, 4 neighboring car, 1 unclear |
| Unseen camera | False free (20) | 20 low contrast |
| Unseen camera | False occupied (20) | 20 lighting |

## Limitations

- Three cameras, two sites, and one held-out camera whose reference was poor. A better PUCPR reference could change its result substantially.
- UFPR04 and UFPR05 are two views of the same lot.
- Bounding boxes of tilted spaces include neighboring areas; rectangles drawn by hand would differ.
- The adaptive baseline's chosen learning rate and ROI scale are at the edge of the searched range.
- PKLot covers about two months per camera, between roughly 05:00 and 22:00, with no overnight, snow or labeled shadow data.
- A learned detector is not justified yet. Most sampled errors come from lighting and low contrast, so brightness normalization and color differences should be tried first.

## Reproduce

Download PKLot, extract it, and run from the repository root in MATLAB:

```matlab
addpath(pwd, fullfile(pwd,'evaluation'))
importPKLot('PKLot/PKLot', 'manifest')
runEvaluation('manifest', 'PKLot/PKLot', 'results', Predictions='results/predictions.csv')
reviewErrors('results/predictions.csv', 'manifest', 'PKLot/PKLot', 'review')
```

`runEvaluation` also writes `tuning.csv`; that file, the predictions and the contact sheets are not committed. The synthetic tests for this folder:

```matlab
results = runtests('evaluation/testEvaluation.m');
assert(~isempty(results), 'No tests discovered.');
assert(all([results.Passed]), 'Some tests failed.');
```

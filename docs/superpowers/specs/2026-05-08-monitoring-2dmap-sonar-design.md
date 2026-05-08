# Monitoring page — 2D Map and Sonar Image panels

**Status**: design
**Author**: ham753261@gmail.com
**Date**: 2026-05-08
**Affected package**: `pkrc_visualizer`

## Goal

Replace the two empty/placeholder panels on the Monitoring page of
`pkrc_visualizer` with live visualizations:

1. **2D Map panel** — render the active SLAM stack's occupancy grid
   (Cartographer or FastLIO localization, whichever is publishing) and
   overlay the robot's pose with TF axes, heading arrow, and a 30-second
   trail.
2. **Sonar Image panel** — render the polar sonar image, mirroring the
   look of the existing Sonar Image page. Auto-detect which of the two
   Oculus units (m750d / m3000d) is publishing.

The change is contained to the Monitoring page. No other page is
modified.

## Non-goals

- Mode switching UI (toggle between Cartographer / FastLIO views). Both
  topics are subscribed in parallel; whichever publishes wins.
- Manual sonar topic selection in the Monitoring panel. The Sonar Image
  page already provides this; the Monitoring panel auto-detects.
- New TF or ROS-client APIs. Only existing utilities
  (`lookup_map_from_odom`, `apply_to_pose`) are used.
- Mini-3D rendering. The SLAM page already does that — this is a
  separate, lightweight 2D top-down view.

## Architecture

### Components

| Component | Type | Action |
|---|---|---|
| `pages/monitoring/topdown_map_widget.py` | existing widget | extended (occupancy-grid layer, auto-fit, TF axes) |
| `pages/monitoring/sonar_image_widget.py` | new file | wraps `widgets.image_view.ImageView` with monitoring panel chrome |
| `pages/monitoring/sonar_placeholder_widget.py` | existing | deleted (no longer imported) |
| `pages/monitoring_page.py` | existing | dispatch wiring + odometry-to-map TF handler |
| `topic_config.py` | existing | adds 4 topic specs to `MonitoringPage` section |

### Data flow

```
ROS topics                          Page                            Widget
────────────────────────────────────────────────────────────────────────────────
/slam/cartographer/map        ─┐
                                ├→ _dispatch ─→ _map.set_occupancy_grid()
/slam/fast_lio_loc/            ─┘                       │
   occupancy_grid                                       ▼
                                                  OccupancyGrid → QImage
/slam/fast_lio/odometry       ──→ _handle_odom         (cached, redrawn on
                                   ├ lookup_map_from_odom()  paintEvent)
                                   ├ apply_to_pose                  │
                                   └→ set_pose_in_map_frame(x,y,yaw)│
                                                                    ▼
/sensor/sonar/oculus/m750d/   ─┐                              paintEvent:
   image/compressed             ├→ _dispatch ─→ _sonar.set_image_msg()
/sensor/sonar/oculus/m3000d/  ─┘                       │      1. panel bg
   image/compressed                                    ▼      2. occupancy grid
                                                  ImageView   3. grid lines (1m)
                                                       │      4. trail (30s)
                                                       ▼      5. TF axes (X/Y)
                                                  QPixmap.scaled()  6. heading arrow
                                                       │
                                                       ▼
                                                  panel pixmap
```

### Topic subscriptions (`topic_config.py`)

Added to the `MonitoringPage` section (existing entries unchanged):

```python
# 2D map — both engines subscribed; whichever publishes wins
TopicSpec("mon_map_carto",   "/slam/cartographer/map",
          OccupancyGrid, qos_transient_local=True),
TopicSpec("mon_map_fastlio", "/slam/fast_lio_loc/occupancy_grid",
          OccupancyGrid, qos_transient_local=True),

# Sonar image — auto-detect by message arrival
TopicSpec("mon_sonar_m750d",  "/sensor/sonar/oculus/m750d/image/compressed",
          CompressedImage, qos_best_effort=True),
TopicSpec("mon_sonar_m3000d", "/sensor/sonar/oculus/m3000d/image/compressed",
          CompressedImage, qos_best_effort=True),
```

QoS rationale:
- `OccupancyGrid` uses `transient_local` so a Monitoring page opened
  *after* SLAM started still receives the latest map immediately.
- Compressed image uses `best_effort` because sonar publishes at ~30 Hz
  and a few drops are acceptable for monitoring.

## 2D Map widget — `topdown_map_widget.py`

Existing widget extended in place. Coordinate convention changes from
"robot-centered, fixed 5m radius" to "auto-fit to occupancy-grid bounds,
map frame north-up (+x → screen right, +y → screen up)."

### New state on `_MapCanvas`

```python
self._grid_image: QImage | None = None    # OccupancyGrid → QImage cache
self._grid_origin_xy: tuple[float, float] = (0.0, 0.0)  # map-frame metres
self._grid_resolution: float = 0.0        # m / cell
self._grid_size: tuple[int, int] = (0, 0) # (width, height) in cells
```

### New methods

```python
def set_occupancy_grid(self, msg) -> None:
    """nav_msgs/OccupancyGrid → QImage. Convert once per message."""
    # data is int8[]: -1=unknown, 0=free, 100=occupied.
    # Greyscale mapping: -1 → mid-grey (127), 0 → white (255), 100 → black (0).
    # Uses numpy → bytes → QImage.Format_Grayscale8.

def set_pose_in_map_frame(self, x: float, y: float, yaw: float) -> None:
    """Replaces update_pose. Coordinates must already be in map frame."""
```

### Coordinate transform

`_world_to_screen(wx, wy)` is rewritten:

- If a grid is loaded: compute scale so the grid bounding box fits inside
  the panel (preserve aspect — letterbox).
- If no grid yet: fall back to the previous robot-centered 5m radius
  view so an odometry-only fallback still renders something useful.

### `paintEvent` order

1. Panel background (deep navy, rounded corners)
2. Occupancy grid via `QPainter.drawImage` (scaled to grid bounds)
3. 1m grid lines (faint border colour)
4. 30-second trail (cyan polyline)
5. TF axes triad at robot pose: X red, Y green, length 0.5m world
6. Heading arrow (existing blue triangle)

### Empty state

Replace `"/slam/fast_lio/odometry 대기 중"` with
`"맵 대기 중\n(cartographer / fast_lio_loc)"`.

## Sonar Image widget — `sonar_image_widget.py` (new)

```python
"""Monitoring page sonar panel — wraps ImageView with title chrome."""
from PyQt5.QtWidgets import QFrame, QLabel, QVBoxLayout

from pkrc_visualizer.widgets.image_view import ImageView
from pkrc_visualizer.pages.monitoring.common import PANEL_QSS, TITLE_QSS


class SonarImageWidget(QFrame):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setObjectName("StatusPanel")
        self.setStyleSheet(PANEL_QSS)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(10, 8, 10, 10)
        layout.setSpacing(6)

        title = QLabel("🌊 소나 이미지")
        title.setStyleSheet(TITLE_QSS)
        layout.addWidget(title)

        self._view = ImageView()
        self._view.setText("소나 이미지 대기 중\n(m750d / m3000d)")
        layout.addWidget(self._view, 1)

    def set_image_msg(self, msg) -> None:
        """sensor_msgs/Image or CompressedImage."""
        self._view.set_image_msg(msg)
```

The wrapped `ImageView` already handles `cv_bridge` exceptions and
displays its own error text inside the panel. No additional error
handling is needed.

## Page wiring — `monitoring_page.py`

### Imports

```python
from pkrc_visualizer.pages.monitoring.sonar_image_widget import SonarImageWidget
from pkrc_visualizer.tf_transform import apply_to_pose
# remove: SonarPlaceholderWidget import
```

### Widget instantiation

```python
self._sonar = SonarImageWidget()  # was SonarPlaceholderWidget()
```

### Dispatch table additions

```python
self._dispatch = {
    # existing...
    "mon_odom":         self._handle_odom,           # changed: now wraps TF lookup
    # new:
    "mon_map_carto":    self._map.set_occupancy_grid,
    "mon_map_fastlio":  self._map.set_occupancy_grid,
    "mon_sonar_m750d":  self._sonar.set_image_msg,
    "mon_sonar_m3000d": self._sonar.set_image_msg,
}
```

### TF-aware odometry handler

```python
def _handle_odom(self, msg) -> None:
    """Lift odometry (odom frame) → map frame before drawing the robot."""
    pos = msg.pose.pose.position
    ori = msg.pose.pose.orientation

    tf_map_from_odom = self._ros_client.lookup_map_from_odom()
    if tf_map_from_odom is not None:
        position = (pos.x, pos.y, pos.z)
        quat = (ori.x, ori.y, ori.z, ori.w)
        position, quat = apply_to_pose(tf_map_from_odom, position, quat)
        x, y = position[0], position[1]
        yaw = _quat_to_yaw(quat[0], quat[1], quat[2], quat[3])
    else:
        # TF unavailable — fall back to odom coords so we still render.
        x, y = pos.x, pos.y
        yaw = _quat_to_yaw(ori.x, ori.y, ori.z, ori.w)

    self._map.set_pose_in_map_frame(x, y, yaw)
```

`_quat_to_yaw` is the helper already defined inside
`topdown_map_widget.py`. The page imports it directly:

```python
from pkrc_visualizer.pages.monitoring.topdown_map_widget import _quat_to_yaw
```

The leading underscore is a convention, not enforcement — Python allows
the import. Renaming/promoting it is out of scope for this change.

## Empty / error scenarios

| Scenario | Behaviour |
|---|---|
| SLAM not running | No grid; `"맵 대기 중"` text. If odometry arrives, robot arrow renders in fallback (robot-centered) view. |
| SLAM running, TF map↔odom not yet ready | Grid renders; robot pose drawn from odom coords (slight misalignment until TF is published, typically <1s). |
| Both sonar units off | `"소나 이미지 대기 중\n(m750d / m3000d)"` text. |
| One sonar on | Only that sonar renders. |
| Both sonar on | Both render — last-arrived wins. No explicit policy needed; this is the chosen behaviour. |
| `OccupancyGrid` data corrupt | `set_occupancy_grid` raises; caught in dispatch and logged. Widget keeps last good grid. |
| `CompressedImage` decode fails | `ImageView.set_image_msg` shows `"convert failed: ..."` text in-panel. |

## Build sequence (for implementation plan)

1. Add `topic_config.py` entries for the four new topics. Build, confirm
   `ros2 topic echo` style discovery sees the page subscribing.
2. Create `sonar_image_widget.py`. Wire it into `monitoring_page.py`
   (replacing `SonarPlaceholderWidget`). Confirm sonar visible in
   Monitoring panel.
3. Delete `sonar_placeholder_widget.py`.
4. Extend `_MapCanvas` with `set_occupancy_grid` (no auto-fit yet — keep
   robot-centered for now). Wire dispatch. Confirm grid pixels appear in
   the panel under the existing pose arrow.
5. Add `set_pose_in_map_frame` and the page-side `_handle_odom` TF
   wrapper. Confirm pose stays aligned with grid as robot moves.
6. Switch `_world_to_screen` to auto-fit on grid bounds. Confirm full
   map fills the panel.
7. Add TF axes overlay (X red / Y green, 0.5m world length).
8. Update empty-state text in `_MapCanvas`.
9. Bump `package.xml` version and update `CHANGELOG.md` per repo
   conventions. Commit messages: one per task, conventional-commit style.

## Verification

- Manual: open Monitoring page with Cartographer running → map renders,
  robot pose aligned with map, axes visible, trail accumulates.
- Manual: same with FastLIO localization → identical behaviour from a
  different topic.
- Manual: kill SLAM mid-run → grid persists (last good), robot keeps
  moving, no crash.
- Manual: turn one sonar off → other one still renders.
- Manual: resize the window (16:9 lock from prior change) → letterboxing
  preserves grid aspect, sonar pixmap scales correctly.

## Open questions / risks

- Greyscale-only occupancy grid is the simplest mapping. If unknown
  cells (-1) need a distinct visual treatment (e.g. pale blue) we can
  switch to RGBA in a follow-up; not in scope here.
- If both sonars publish simultaneously at high rate, the panel may
  visibly oscillate between the two images. Accepted; if it becomes a
  problem in operations, a "stick to last source for N seconds" debounce
  can be added without changing the topic-config layout.
- TF lookup is synchronous on the GUI thread. `lookup_map_from_odom`
  uses zero timeout, so it's effectively non-blocking; same pattern as
  SLAM page already in production.

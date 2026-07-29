# Monitoring page 2D Map + Sonar Image Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace two empty placeholder panels on the Monitoring page with live visualizations: a top-down 2D occupancy-grid map (with robot pose, TF axes, 30s trail) and a sonar polar image (auto-detect m750d/m3000d).

**Architecture:** Page-level dispatch. Existing `TopdownMapWidget` is extended in place (QPainter custom drawing); new `SonarImageWidget` wraps the existing `widgets.image_view.ImageView`. Both engines (Cartographer + FastLIO localization) are subscribed in parallel; whichever publishes wins, mirroring the SLAM page's pattern.

**Tech Stack:** PyQt5 / QPainter / numpy / cv_bridge / ROS 2 (rclpy, nav_msgs/OccupancyGrid, sensor_msgs/CompressedImage, sensor_msgs/Image, nav_msgs/Odometry).

**Spec:** [docs/superpowers/specs/2026-05-08-monitoring-2dmap-sonar-design.md](../specs/2026-05-08-monitoring-2dmap-sonar-design.md)

**Branch:** continue on the current development branch (`docs/topic-audit-and-rename-plan`) is acceptable for the design discussion above, but implementation should run on a fresh feature branch — see Task 0.

---

## Task 0: Branch setup

**Files:**
- None (git only)

- [ ] **Step 1: Create feature branch**

```bash
cd /home/hero/ros2_ws
git checkout main
git pull --ff-only
git checkout -b feat/monitoring-2dmap-sonar
```

Expected: clean working tree on the new branch.

- [ ] **Step 2: Sanity-build before any change**

```bash
colcon build --packages-select pkrc_visualizer --symlink-install
```

Expected: `Finished <<< pkrc_visualizer [...]`. Any failure here is unrelated to this plan and must be fixed (or reported) first.

---

## Task 1: Topic-config additions

**Files:**
- Modify: `src/pkrc_visualizer/pkrc_visualizer/topic_config.py:56-67`
- Test: `src/pkrc_visualizer/test/test_topic_config_monitoring.py` (new)

- [ ] **Step 1: Write the failing test**

Create `src/pkrc_visualizer/test/test_topic_config_monitoring.py`:

```python
"""topic_config: Monitoring page exposes 2D-map + sonar topic specs."""
from nav_msgs.msg import OccupancyGrid
from sensor_msgs.msg import CompressedImage

from pkrc_visualizer.topic_config import TOPICS


def _by_id(specs, topic_id):
    for s in specs:
        if s.topic_id == topic_id:
            return s
    raise KeyError(topic_id)


def test_monitoring_has_map_carto():
    spec = _by_id(TOPICS["monitoring"], "mon_map_carto")
    assert spec.topic_name == "/slam/cartographer/map"
    assert spec.msg_type is OccupancyGrid
    assert spec.qos_transient_local is True
    assert spec.qos_best_effort is False


def test_monitoring_has_map_fastlio():
    spec = _by_id(TOPICS["monitoring"], "mon_map_fastlio")
    assert spec.topic_name == "/slam/fast_lio_loc/occupancy_grid"
    assert spec.msg_type is OccupancyGrid
    assert spec.qos_transient_local is True


def test_monitoring_has_sonar_m750d():
    spec = _by_id(TOPICS["monitoring"], "mon_sonar_m750d")
    assert spec.topic_name == "/sensor/sonar/oculus/m750d/image/compressed"
    assert spec.msg_type is CompressedImage
    assert spec.qos_best_effort is True


def test_monitoring_has_sonar_m3000d():
    spec = _by_id(TOPICS["monitoring"], "mon_sonar_m3000d")
    assert spec.topic_name == "/sensor/sonar/oculus/m3000d/image/compressed"
    assert spec.msg_type is CompressedImage
    assert spec.qos_best_effort is True
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd /home/hero/ros2_ws
colcon test --packages-select pkrc_visualizer --pytest-args -k test_topic_config_monitoring -v
colcon test-result --verbose --test-result-base build/pkrc_visualizer
```

Expected: 4 KeyError failures (`'mon_map_carto'` etc.).

- [ ] **Step 3: Add the 4 entries**

In `src/pkrc_visualizer/pkrc_visualizer/topic_config.py`, append to the `"monitoring"` list (currently ending at line 66). Insert these lines just before the closing `]` at line 67:

```python
        # 2D map sources — both engines subscribed in parallel; whichever
        # SLAM stack is running publishes. transient_local so a Monitoring
        # page opened *after* SLAM started still receives the latest map.
        TopicSpec("mon_map_carto",   "/slam/cartographer/map",
                  OccupancyGrid, qos_transient_local=True),
        TopicSpec("mon_map_fastlio", "/slam/fast_lio_loc/occupancy_grid",
                  OccupancyGrid, qos_transient_local=True),
        # Sonar polar image — auto-detect by message arrival.
        TopicSpec("mon_sonar_m750d",  "/sensor/sonar/oculus/m750d/image/compressed",
                  CompressedImage, qos_best_effort=True),
        TopicSpec("mon_sonar_m3000d", "/sensor/sonar/oculus/m3000d/image/compressed",
                  CompressedImage, qos_best_effort=True),
```

`OccupancyGrid` and `CompressedImage` are already imported at lines 5–6.

- [ ] **Step 4: Run test — expect PASS**

```bash
colcon test --packages-select pkrc_visualizer --pytest-args -k test_topic_config_monitoring -v
colcon test-result --verbose --test-result-base build/pkrc_visualizer
```

Expected: 4 passed.

- [ ] **Step 5: Commit**

```bash
git add src/pkrc_visualizer/pkrc_visualizer/topic_config.py \
        src/pkrc_visualizer/test/test_topic_config_monitoring.py
git commit -m "feat(monitoring): subscribe to occupancy-grid + sonar topics"
```

---

## Task 2: SonarImageWidget (new file)

**Files:**
- Create: `src/pkrc_visualizer/pkrc_visualizer/pages/monitoring/sonar_image_widget.py`
- Test: `src/pkrc_visualizer/test/test_sonar_image_widget.py` (new)

- [ ] **Step 1: Write the failing test**

Create `src/pkrc_visualizer/test/test_sonar_image_widget.py`:

```python
"""SonarImageWidget: title bar + ImageView wrapping."""
import numpy as np
from PyQt5.QtWidgets import QLabel
from sensor_msgs.msg import Image

from pkrc_visualizer.pages.monitoring.sonar_image_widget import \
    SonarImageWidget
from pkrc_visualizer.widgets.image_view import ImageView


def test_constructs_with_title_and_view(qtbot):
    w = SonarImageWidget()
    qtbot.addWidget(w)
    labels = w.findChildren(QLabel)
    titles = [lab.text() for lab in labels if "소나" in lab.text()]
    assert titles, "expected '소나' in some QLabel"
    views = w.findChildren(ImageView)
    assert len(views) == 1


def test_empty_state_text_is_korean(qtbot):
    w = SonarImageWidget()
    qtbot.addWidget(w)
    view = w.findChildren(ImageView)[0]
    assert "대기 중" in view.text()


def test_set_image_msg_forwards_to_view(qtbot):
    w = SonarImageWidget()
    qtbot.addWidget(w)
    msg = Image()
    msg.height = 4
    msg.width = 4
    msg.encoding = "rgb8"
    msg.step = 12
    msg.data = (np.zeros((4, 4, 3), dtype=np.uint8)).tobytes()
    w.set_image_msg(msg)
    view = w.findChildren(ImageView)[0]
    assert view.pixmap() is not None
```

- [ ] **Step 2: Run test — expect FAIL (ModuleNotFoundError)**

```bash
colcon test --packages-select pkrc_visualizer --pytest-args -k test_sonar_image_widget -v
colcon test-result --verbose --test-result-base build/pkrc_visualizer
```

Expected: `ModuleNotFoundError: No module named '...sonar_image_widget'`.

- [ ] **Step 3: Create the widget**

Create `src/pkrc_visualizer/pkrc_visualizer/pages/monitoring/sonar_image_widget.py`:

```python
"""Monitoring page sonar panel — wraps ImageView with title chrome.

Subscribed via the page's dispatch table for two topics in parallel:
m750d and m3000d. Whichever message arrives is rendered.
"""
from PyQt5.QtWidgets import QFrame, QLabel, QVBoxLayout

from pkrc_visualizer.pages.monitoring.common import PANEL_QSS, TITLE_QSS
from pkrc_visualizer.widgets.image_view import ImageView


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

- [ ] **Step 4: Run test — expect PASS**

```bash
colcon build --packages-select pkrc_visualizer --symlink-install
colcon test --packages-select pkrc_visualizer --pytest-args -k test_sonar_image_widget -v
colcon test-result --verbose --test-result-base build/pkrc_visualizer
```

Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add src/pkrc_visualizer/pkrc_visualizer/pages/monitoring/sonar_image_widget.py \
        src/pkrc_visualizer/test/test_sonar_image_widget.py
git commit -m "feat(monitoring): add SonarImageWidget wrapping ImageView"
```

---

## Task 3: Wire SonarImageWidget into MonitoringPage and delete placeholder

**Files:**
- Modify: `src/pkrc_visualizer/pkrc_visualizer/pages/monitoring_page.py`
- Delete: `src/pkrc_visualizer/pkrc_visualizer/pages/monitoring/sonar_placeholder_widget.py`
- Test: `src/pkrc_visualizer/test/test_monitoring_page_dispatch.py` (new)

- [ ] **Step 1: Write the failing test**

Create `src/pkrc_visualizer/test/test_monitoring_page_dispatch.py`:

```python
"""MonitoringPage: dispatch table includes new map + sonar entries.

Construction requires a stub ros_client that exposes the methods the
page uses; we don't actually run any ROS spin here.
"""
from unittest.mock import MagicMock

from pkrc_visualizer.pages.monitoring.sonar_image_widget import \
    SonarImageWidget
from pkrc_visualizer.pages.monitoring_page import MonitoringPage


def _stub_ros_client():
    rc = MagicMock()
    rc.lookup_map_from_odom.return_value = None
    return rc


def test_page_uses_sonar_image_widget(qtbot):
    page = MonitoringPage(_stub_ros_client())
    qtbot.addWidget(page)
    assert isinstance(page._sonar, SonarImageWidget)


def test_dispatch_has_sonar_entries(qtbot):
    page = MonitoringPage(_stub_ros_client())
    qtbot.addWidget(page)
    assert "mon_sonar_m750d" in page._dispatch
    assert "mon_sonar_m3000d" in page._dispatch
    # Both route to the sonar widget's set_image_msg
    assert page._dispatch["mon_sonar_m750d"] == page._sonar.set_image_msg
    assert page._dispatch["mon_sonar_m3000d"] == page._sonar.set_image_msg
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
colcon test --packages-select pkrc_visualizer --pytest-args -k test_monitoring_page_dispatch -v
colcon test-result --verbose --test-result-base build/pkrc_visualizer
```

Expected: `AssertionError: assert isinstance(page._sonar, SonarImageWidget)` (currently it's `SonarPlaceholderWidget`).

- [ ] **Step 3: Update imports and instantiation in `monitoring_page.py`**

In `src/pkrc_visualizer/pkrc_visualizer/pages/monitoring_page.py`:

Replace lines 18–19:

```python
from pkrc_visualizer.pages.monitoring.sonar_placeholder_widget import \
    SonarPlaceholderWidget
```

with:

```python
from pkrc_visualizer.pages.monitoring.sonar_image_widget import \
    SonarImageWidget
```

Replace line 55:

```python
        self._sonar = SonarPlaceholderWidget()
```

with:

```python
        self._sonar = SonarImageWidget()
```

In the `self._dispatch` dict (currently lines 73–84), add two new entries before the closing brace. The dict becomes:

```python
        self._dispatch = {
            "mon_camera":       self._camera.update_from_msg,
            "mon_odom":         self._map.update_from_msg,
            "mon_joy":          self._joy.update_from_msg,
            "mon_motors":       self._motors.update_from_msg,
            "mon_relays":       self._relays.update_from_msg,
            "mon_battery":      self._battery.update_from_msg,
            "mon_system":       self._sys_led.update_system,
            "mon_led":          self._sys_led.update_led,
            "mon_tilt_cur":     self._tilt.update_current,
            "mon_tilt_goal":    self._tilt.update_goal,
            "mon_sonar_m750d":  self._sonar.set_image_msg,
            "mon_sonar_m3000d": self._sonar.set_image_msg,
        }
```

(The `mon_odom` entry is unchanged in this task — it's rewired in Task 5.)

- [ ] **Step 4: Run test — expect PASS**

```bash
colcon build --packages-select pkrc_visualizer --symlink-install
colcon test --packages-select pkrc_visualizer --pytest-args -k test_monitoring_page_dispatch -v
colcon test-result --verbose --test-result-base build/pkrc_visualizer
```

Expected: 2 passed.

- [ ] **Step 5: Delete the placeholder widget**

```bash
git rm src/pkrc_visualizer/pkrc_visualizer/pages/monitoring/sonar_placeholder_widget.py
```

- [ ] **Step 6: Verify no other references**

```bash
grep -rn "SonarPlaceholderWidget\|sonar_placeholder_widget" src/pkrc_visualizer/
```

Expected: no output (empty result).

- [ ] **Step 7: Rebuild + run all monitoring-related tests**

```bash
colcon build --packages-select pkrc_visualizer --symlink-install
colcon test --packages-select pkrc_visualizer --pytest-args -k "monitoring or sonar_image_widget or topic_config" -v
colcon test-result --verbose --test-result-base build/pkrc_visualizer
```

Expected: all tests in those modules pass.

- [ ] **Step 8: Commit**

```bash
git add src/pkrc_visualizer/pkrc_visualizer/pages/monitoring_page.py \
        src/pkrc_visualizer/test/test_monitoring_page_dispatch.py
git commit -m "feat(monitoring): wire SonarImageWidget into page, drop placeholder"
```

---

## Task 4: `_MapCanvas.set_occupancy_grid` (no auto-fit yet)

**Files:**
- Modify: `src/pkrc_visualizer/pkrc_visualizer/pages/monitoring/topdown_map_widget.py`
- Modify: `src/pkrc_visualizer/pkrc_visualizer/pages/monitoring_page.py` (dispatch wiring)
- Test: `src/pkrc_visualizer/test/test_topdown_map_widget.py` (new)

- [ ] **Step 1: Write the failing test**

Create `src/pkrc_visualizer/test/test_topdown_map_widget.py`:

```python
"""TopdownMapWidget: occupancy-grid → QImage conversion."""
import numpy as np
from nav_msgs.msg import OccupancyGrid

from pkrc_visualizer.pages.monitoring.topdown_map_widget import (
    TopdownMapWidget, _occupancy_grid_to_qimage)


def _make_grid(width, height, cells, resolution=0.1, ox=0.0, oy=0.0):
    msg = OccupancyGrid()
    msg.info.width = width
    msg.info.height = height
    msg.info.resolution = resolution
    msg.info.origin.position.x = ox
    msg.info.origin.position.y = oy
    msg.info.origin.orientation.w = 1.0
    msg.data = list(cells)
    return msg


def test_grid_to_qimage_unknown_is_grey():
    cells = [-1] * (3 * 3)
    msg = _make_grid(3, 3, cells)
    img = _occupancy_grid_to_qimage(msg)
    assert img.width() == 3 and img.height() == 3
    # Sample one pixel — Format_Grayscale8, all unknown → 127
    assert img.pixel(0, 0) & 0xFF == 127


def test_grid_to_qimage_free_is_white():
    cells = [0] * (3 * 3)
    img = _occupancy_grid_to_qimage(_make_grid(3, 3, cells))
    assert img.pixel(0, 0) & 0xFF == 255


def test_grid_to_qimage_occupied_is_black():
    cells = [100] * (3 * 3)
    img = _occupancy_grid_to_qimage(_make_grid(3, 3, cells))
    assert img.pixel(0, 0) & 0xFF == 0


def test_grid_to_qimage_y_flipped():
    # Bottom row (data row 0) is occupied; top row (data row H-1) is free.
    cells = [100, 100, 100,    # row 0 (bottom in world)
             50, 50, 50,
             0, 0, 0]           # row 2 (top in world)
    img = _occupancy_grid_to_qimage(_make_grid(3, 3, cells))
    # In QImage coords (y=0 is top), pixel(0,0) should be the FREE row.
    assert img.pixel(0, 0) & 0xFF == 255
    assert img.pixel(0, 2) & 0xFF == 0


def test_set_occupancy_grid_caches_metadata(qtbot):
    w = TopdownMapWidget()
    qtbot.addWidget(w)
    msg = _make_grid(4, 5, [0] * 20, resolution=0.25, ox=-1.0, oy=-2.0)
    w.set_occupancy_grid(msg)
    canvas = w._canvas
    assert canvas._grid_size == (4, 5)
    assert canvas._grid_resolution == 0.25
    assert canvas._grid_origin_xy == (-1.0, -2.0)
    assert canvas._grid_image is not None
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
colcon test --packages-select pkrc_visualizer --pytest-args -k test_topdown_map_widget -v
colcon test-result --verbose --test-result-base build/pkrc_visualizer
```

Expected: `ImportError: cannot import name '_occupancy_grid_to_qimage'`.

- [ ] **Step 3: Add `_occupancy_grid_to_qimage` and grid state to widget**

Edit `src/pkrc_visualizer/pkrc_visualizer/pages/monitoring/topdown_map_widget.py`:

a) Add imports near the top (line 9–15 area), so the imports block becomes:

```python
import math
import time
from collections import deque
from typing import Optional

import numpy as np
from PyQt5.QtCore import QPointF, QRectF, Qt
from PyQt5.QtGui import QColor, QFont, QImage, QPainter, QPen, QPolygonF
from PyQt5.QtWidgets import QFrame, QLabel, QVBoxLayout, QWidget
```

b) Add a module-level helper function after the existing `_quat_to_yaw` (after line 33):

```python
def _occupancy_grid_to_qimage(msg) -> QImage:
    """nav_msgs/OccupancyGrid → QImage (Format_Grayscale8).

    Greyscale mapping:
      -1 (unknown) → 127 (mid grey)
       0 (free)    → 255 (white)
     100 (occupied) → 0 (black)
      others       → linearly interpolated.

    OccupancyGrid data is row-major with row 0 at the LOWER-LEFT cell
    (origin pose). QImage uses TOP-LEFT origin, so we flip vertically
    so that drawImage(rect, img) renders north-up.
    """
    w = msg.info.width
    h = msg.info.height
    data = np.asarray(msg.data, dtype=np.int16).reshape(h, w)
    # -1 → 127; 0..100 → 255..0 linearly
    out = np.where(data < 0, 127, 255 - (data * 255) // 100)
    out = np.clip(out, 0, 255).astype(np.uint8)
    out = np.flipud(out)  # row 0 of image = top of map (high world y)
    flat = bytes(out.tobytes())  # detach from numpy buffer lifetime
    return QImage(flat, w, h, w, QImage.Format_Grayscale8).copy()
```

c) Add new state to `_MapCanvas.__init__` (currently lines 36–44). Add after `self._trail` line:

```python
        # Occupancy-grid layer (drawn behind grid lines / trail / robot).
        self._grid_image: Optional[QImage] = None
        self._grid_origin_xy: tuple[float, float] = (0.0, 0.0)
        self._grid_resolution: float = 0.0
        self._grid_size: tuple[int, int] = (0, 0)
```

d) Add a method on `_MapCanvas` (place it just after `update_pose`, around line 56):

```python
    def set_occupancy_grid(self, msg) -> None:
        """Cache grid as QImage + metadata; trigger repaint."""
        self._grid_image = _occupancy_grid_to_qimage(msg)
        self._grid_origin_xy = (
            float(msg.info.origin.position.x),
            float(msg.info.origin.position.y),
        )
        self._grid_resolution = float(msg.info.resolution)
        self._grid_size = (int(msg.info.width), int(msg.info.height))
        self.update()
```

e) In `paintEvent` (currently lines 73–149), insert a "draw grid" block immediately after the panel background (after line 79) and before the grid-line drawing. Add a helper method on `_MapCanvas` (place it just above `paintEvent`):

```python
    def _paint_grid(self, p: QPainter) -> None:
        if self._grid_image is None:
            return
        W, H = self._grid_size
        res = self._grid_resolution
        if W == 0 or H == 0 or res <= 0.0:
            return
        ox, oy = self._grid_origin_xy
        # Top-left world: (ox, oy + H*res). Bottom-right world: (ox+W*res, oy).
        tl = self._world_to_screen(ox, oy + H * res)
        br = self._world_to_screen(ox + W * res, oy)
        rect = QRectF(tl.x(), tl.y(), br.x() - tl.x(), br.y() - tl.y())
        p.drawImage(rect, self._grid_image)
```

In `paintEvent`, modify the section right after the background fill. Find these existing lines (around line 76–80):

```python
        # Background — deep navy with rounded corners
        p.setPen(Qt.NoPen)
        p.setBrush(QColor(PANEL_BG_INNER))
        p.drawRoundedRect(self.rect(), 6, 6)
        # Grid
```

Insert the grid call between the background and the "# Grid" comment, so the section reads:

```python
        # Background — deep navy with rounded corners
        p.setPen(Qt.NoPen)
        p.setBrush(QColor(PANEL_BG_INNER))
        p.drawRoundedRect(self.rect(), 6, 6)
        # Occupancy grid (behind everything else)
        self._paint_grid(p)
        # Grid
```

f) Add a public method on `TopdownMapWidget` (the QFrame wrapper, currently lines 152–172) that delegates to the canvas. Add after `update_from_msg` (after line 171):

```python
    def set_occupancy_grid(self, msg) -> None:
        """nav_msgs/OccupancyGrid pass-through to canvas."""
        self._canvas.set_occupancy_grid(msg)
```

- [ ] **Step 4: Wire dispatch in `monitoring_page.py`**

In `src/pkrc_visualizer/pkrc_visualizer/pages/monitoring_page.py`, add two entries to `self._dispatch` (just before `mon_sonar_m750d`):

```python
            "mon_map_carto":    self._map.set_occupancy_grid,
            "mon_map_fastlio":  self._map.set_occupancy_grid,
```

So the dispatch dict becomes:

```python
        self._dispatch = {
            "mon_camera":       self._camera.update_from_msg,
            "mon_odom":         self._map.update_from_msg,
            "mon_joy":          self._joy.update_from_msg,
            "mon_motors":       self._motors.update_from_msg,
            "mon_relays":       self._relays.update_from_msg,
            "mon_battery":      self._battery.update_from_msg,
            "mon_system":       self._sys_led.update_system,
            "mon_led":          self._sys_led.update_led,
            "mon_tilt_cur":     self._tilt.update_current,
            "mon_tilt_goal":    self._tilt.update_goal,
            "mon_map_carto":    self._map.set_occupancy_grid,
            "mon_map_fastlio":  self._map.set_occupancy_grid,
            "mon_sonar_m750d":  self._sonar.set_image_msg,
            "mon_sonar_m3000d": self._sonar.set_image_msg,
        }
```

- [ ] **Step 5: Run tests — expect PASS**

```bash
colcon build --packages-select pkrc_visualizer --symlink-install
colcon test --packages-select pkrc_visualizer --pytest-args -k test_topdown_map_widget -v
colcon test-result --verbose --test-result-base build/pkrc_visualizer
```

Expected: 5 passed.

- [ ] **Step 6: Manual smoke test**

```bash
source /home/hero/ros2_ws/install/setup.bash
ros2 launch pkrc_visualizer pkrc_visualizer.launch.py
```

In another shell, replay any bag containing `/slam/cartographer/map` or `/slam/fast_lio_loc/occupancy_grid` (or run live SLAM). Expected: greyscale grid pixels appear under the existing trail/arrow on the Monitoring page's "🗺 2D 맵" panel. Alignment may look off at this stage — that's expected, fixed in Task 6.

- [ ] **Step 7: Commit**

```bash
git add src/pkrc_visualizer/pkrc_visualizer/pages/monitoring/topdown_map_widget.py \
        src/pkrc_visualizer/pkrc_visualizer/pages/monitoring_page.py \
        src/pkrc_visualizer/test/test_topdown_map_widget.py
git commit -m "feat(monitoring): render occupancy grid behind robot pose"
```

---

## Task 5: TF-aware odometry handler (`set_pose_in_map_frame` + `_handle_odom`)

**Files:**
- Modify: `src/pkrc_visualizer/pkrc_visualizer/pages/monitoring/topdown_map_widget.py`
- Modify: `src/pkrc_visualizer/pkrc_visualizer/pages/monitoring_page.py`
- Modify: `src/pkrc_visualizer/test/test_monitoring_page_dispatch.py`

- [ ] **Step 1: Write the failing test (extend the existing dispatch test file)**

Append to `src/pkrc_visualizer/test/test_monitoring_page_dispatch.py`:

```python
import numpy as np
from nav_msgs.msg import Odometry


def _identity_4x4():
    return np.eye(4, dtype=np.float64)


def _odom_at(x, y, yaw=0.0):
    msg = Odometry()
    msg.pose.pose.position.x = x
    msg.pose.pose.position.y = y
    msg.pose.pose.orientation.z = float(np.sin(yaw / 2.0))
    msg.pose.pose.orientation.w = float(np.cos(yaw / 2.0))
    return msg


def test_handle_odom_uses_tf_when_available(qtbot):
    rc = MagicMock()
    # tf_map_from_odom: translate (+10, +20, 0)
    tf = _identity_4x4()
    tf[0, 3] = 10.0
    tf[1, 3] = 20.0
    rc.lookup_map_from_odom.return_value = tf

    page = MonitoringPage(rc)
    qtbot.addWidget(page)

    page._handle_odom(_odom_at(1.0, 2.0))
    canvas = page._map._canvas
    assert canvas._x == 11.0
    assert canvas._y == 22.0


def test_handle_odom_falls_back_when_no_tf(qtbot):
    rc = MagicMock()
    rc.lookup_map_from_odom.return_value = None

    page = MonitoringPage(rc)
    qtbot.addWidget(page)

    page._handle_odom(_odom_at(3.0, 4.0))
    canvas = page._map._canvas
    assert canvas._x == 3.0
    assert canvas._y == 4.0


def test_dispatch_routes_mon_odom_to_handle_odom(qtbot):
    rc = MagicMock()
    rc.lookup_map_from_odom.return_value = None
    page = MonitoringPage(rc)
    qtbot.addWidget(page)
    assert page._dispatch["mon_odom"] == page._handle_odom
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
colcon test --packages-select pkrc_visualizer --pytest-args -k test_monitoring_page_dispatch -v
colcon test-result --verbose --test-result-base build/pkrc_visualizer
```

Expected: failures for `_handle_odom` not existing / dispatch still pointing to `update_from_msg`.

- [ ] **Step 3: Add `set_pose_in_map_frame` (keep `update_from_msg` for now)**

In `src/pkrc_visualizer/pkrc_visualizer/pages/monitoring/topdown_map_widget.py`, add a method on `_MapCanvas` (just after `update_pose`, around line 56):

```python
    def set_pose_in_map_frame(self, x: float, y: float, yaw: float) -> None:
        """Equivalent to update_pose. Explicit name documents the frame
        contract: callers must provide map-frame coords (page does the
        odom→map TF lift)."""
        self.update_pose(x, y, yaw)
```

On the `TopdownMapWidget` wrapper class, add the corresponding pass-through method **alongside** the existing `update_from_msg` (do NOT delete `update_from_msg` yet — that happens in Step 6 after dispatch is rewired):

```python
    def set_pose_in_map_frame(self, x: float, y: float, yaw: float) -> None:
        self._canvas.set_pose_in_map_frame(x, y, yaw)
```

- [ ] **Step 4: Add `_handle_odom` on the page**

In `src/pkrc_visualizer/pkrc_visualizer/pages/monitoring_page.py`:

a) Add imports at the top (after existing imports, around line 23):

```python
from pkrc_visualizer.pages.monitoring.topdown_map_widget import _quat_to_yaw
from pkrc_visualizer.tf_transform import apply_to_pose
```

b) Add a method on `MonitoringPage` (place it after `__init__`, before `_is_my_topic` around line 86):

```python
    def _handle_odom(self, msg) -> None:
        """Lift odometry from odom frame to map frame before drawing.

        Uses the existing ros_client.lookup_map_from_odom() (zero-timeout,
        non-blocking). If TF is unavailable, fall back to odom coords —
        the robot still renders, just with a slight misalignment to the
        grid until TF becomes available (typically <1s after SLAM start).
        """
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
            x, y = pos.x, pos.y
            yaw = _quat_to_yaw(ori.x, ori.y, ori.z, ori.w)
        self._map.set_pose_in_map_frame(x, y, yaw)
```

c) Change the dispatch entry for `mon_odom` from `self._map.update_from_msg` to `self._handle_odom`:

```python
            "mon_odom":         self._handle_odom,
```

- [ ] **Step 5: Run tests — expect PASS**

```bash
colcon build --packages-select pkrc_visualizer --symlink-install
colcon test --packages-select pkrc_visualizer --pytest-args -k test_monitoring_page_dispatch -v
colcon test-result --verbose --test-result-base build/pkrc_visualizer
```

Expected: all pass.

- [ ] **Step 6: Delete the now-unused `update_from_msg`**

After Step 4(c), nothing calls `TopdownMapWidget.update_from_msg` anymore (the dispatch points to `_handle_odom`, which calls `set_pose_in_map_frame`). Delete the method body (currently lines ~166–171 of `topdown_map_widget.py`):

```python
    def update_from_msg(self, msg) -> None:
        # nav_msgs/Odometry — pose.pose.position + pose.pose.orientation
        pos = msg.pose.pose.position
        ori = msg.pose.pose.orientation
        yaw = _quat_to_yaw(ori.x, ori.y, ori.z, ori.w)
        self._canvas.update_pose(float(pos.x), float(pos.y), yaw)
```

Verify nothing else references it:

```bash
grep -rn "update_from_msg" src/pkrc_visualizer/pkrc_visualizer/pages/monitoring/topdown_map_widget.py \
                            src/pkrc_visualizer/pkrc_visualizer/pages/monitoring_page.py
```

Expected: no output. (Other monitoring widgets have their own `update_from_msg`; we only check these two files.)

Re-run the test suite to confirm no regression:

```bash
colcon build --packages-select pkrc_visualizer --symlink-install
colcon test --packages-select pkrc_visualizer --pytest-args -k "monitoring or topdown_map_widget" -v
colcon test-result --verbose --test-result-base build/pkrc_visualizer
```

Expected: all pass.

- [ ] **Step 7: Manual smoke test**

Run live SLAM (or replay a bag with both odometry and TF). Expected: robot arrow stays anchored to its real-world position on the grid as the boat moves; trail accumulates on the grid background. With Cartographer running, the same behaviour from `/slam/cartographer/map`.

- [ ] **Step 8: Commit**

```bash
git add src/pkrc_visualizer/pkrc_visualizer/pages/monitoring/topdown_map_widget.py \
        src/pkrc_visualizer/pkrc_visualizer/pages/monitoring_page.py \
        src/pkrc_visualizer/test/test_monitoring_page_dispatch.py
git commit -m "feat(monitoring): lift odometry to map frame via TF"
```

---

## Task 6: Auto-fit world-to-screen transform

**Files:**
- Modify: `src/pkrc_visualizer/pkrc_visualizer/pages/monitoring/topdown_map_widget.py`
- Modify: `src/pkrc_visualizer/test/test_topdown_map_widget.py`

- [ ] **Step 1: Append failing tests to the existing test file**

Append to `src/pkrc_visualizer/test/test_topdown_map_widget.py`:

```python
def test_world_to_screen_autofits_grid(qtbot):
    """With a grid loaded, the grid bounding box must fit inside the panel."""
    w = TopdownMapWidget()
    qtbot.addWidget(w)
    w.show()
    w.resize(400, 300)

    # 10×10 cells × 0.5 m = 5 m × 5 m grid, origin at (0, 0).
    msg = _make_grid(10, 10, [0] * 100, resolution=0.5, ox=0.0, oy=0.0)
    w.set_occupancy_grid(msg)
    canvas = w._canvas

    # Grid corners in map frame:
    #   bottom-left  = (0, 0)
    #   top-right    = (5, 5)
    bl = canvas._world_to_screen(0.0, 0.0)
    tr = canvas._world_to_screen(5.0, 5.0)

    # Both must be within the canvas.
    assert 0 <= bl.x() <= canvas.width()
    assert 0 <= bl.y() <= canvas.height()
    assert 0 <= tr.x() <= canvas.width()
    assert 0 <= tr.y() <= canvas.height()
    # +x → screen right (so tr.x > bl.x), +y → screen up (so tr.y < bl.y).
    assert tr.x() > bl.x()
    assert tr.y() < bl.y()


def test_world_to_screen_centers_grid_in_wide_panel(qtbot):
    """Aspect preserved: 5m×5m grid in 400×200 panel leaves equal H margins."""
    w = TopdownMapWidget()
    qtbot.addWidget(w)
    w.show()
    w.resize(400, 200)
    msg = _make_grid(10, 10, [0] * 100, resolution=0.5)
    w.set_occupancy_grid(msg)
    canvas = w._canvas

    # Square grid in 2:1 panel → vertical fit; horizontal margins on both sides.
    bl = canvas._world_to_screen(0.0, 0.0)   # grid bottom-left
    br = canvas._world_to_screen(5.0, 0.0)   # grid bottom-right
    grid_pix_width = br.x() - bl.x()
    left_margin = bl.x()
    right_margin = canvas.width() - br.x()
    assert abs(left_margin - right_margin) < 1.0  # equal within rounding
    # Grid height should equal canvas height (it's the limiting axis)
    assert grid_pix_width < canvas.width()


def test_world_to_screen_falls_back_without_grid(qtbot):
    """No grid loaded → robot-centered behaviour preserved."""
    w = TopdownMapWidget()
    qtbot.addWidget(w)
    w.show()
    w.resize(400, 400)
    canvas = w._canvas
    canvas.update_pose(0.0, 0.0, 0.0)
    centre = canvas._world_to_screen(0.0, 0.0)
    # Robot-centered: (0,0) world → centre of canvas
    assert abs(centre.x() - canvas.width() / 2) < 1.0
    assert abs(centre.y() - canvas.height() / 2) < 1.0
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
colcon test --packages-select pkrc_visualizer --pytest-args -k "test_world_to_screen" -v
colcon test-result --verbose --test-result-base build/pkrc_visualizer
```

Expected: assertion failures (current `_world_to_screen` is robot-centered regardless of grid).

- [ ] **Step 3: Rewrite `_world_to_screen`**

Replace the existing `_world_to_screen` method in `_MapCanvas` (currently lines 58–71) with:

```python
    def _world_to_screen(self, wx: float, wy: float) -> QPointF:
        """Map (wx, wy) world coords → panel pixel coords.

        Two modes:
        - Auto-fit on grid bounds (north-up). Used when an occupancy grid
          has been loaded. +x_world → screen right, +y_world → screen up.
          Aspect preserved (letterbox).
        - Robot-centered fallback. Used until the first grid arrives. +x
          forward → screen up, +y left → screen left, fixed 5m radius.
        """
        if self._grid_image is not None and self._grid_size[0] > 0 \
                and self._grid_size[1] > 0 and self._grid_resolution > 0.0:
            Pw = float(self.width())
            Ph = float(self.height())
            W, H = self._grid_size
            res = self._grid_resolution
            ox, oy = self._grid_origin_xy
            gw_m = W * res
            gh_m = H * res
            scale = min(Pw / gw_m, Ph / gh_m)
            cx = (Pw - gw_m * scale) / 2.0  # left edge of grid in screen
            cy = (Ph - gh_m * scale) / 2.0  # top edge of grid in screen
            sx = cx + (wx - ox) * scale
            sy = cy + gh_m * scale - (wy - oy) * scale
            return QPointF(sx, sy)

        # Robot-centered fallback (no grid yet).
        cx_pix = self.width() / 2.0
        cy_pix = self.height() / 2.0
        side = min(self.width(), self.height())
        scale = (side / 2.0) / VIEW_HALF_M
        rx = wx - (self._x or 0.0)
        ry = wy - (self._y or 0.0)
        sx = cx_pix - ry * scale
        sy = cy_pix - rx * scale
        return QPointF(sx, sy)
```

- [ ] **Step 4: Update the 1m grid-line drawing for the auto-fit case**

The existing 1m grid lines code in `paintEvent` (around lines 84–101) iterates over a 5m window centred on the robot. With auto-fit it should iterate over the full grid bounds instead. Replace the existing grid-line block (lines 81–101) with:

```python
        # 1m grid lines
        p.setPen(QPen(QColor(PANEL_BORDER), 1))
        if self._grid_image is not None and self._grid_size[0] > 0:
            ox, oy = self._grid_origin_xy
            W, H = self._grid_size
            gw_m = W * self._grid_resolution
            gh_m = H * self._grid_resolution
            x_min = math.floor(ox / GRID_STEP_M) * GRID_STEP_M
            x_max = ox + gw_m
            x = x_min
            while x <= x_max:
                a = self._world_to_screen(x, oy)
                b = self._world_to_screen(x, oy + gh_m)
                p.drawLine(a, b)
                x += GRID_STEP_M
            y_min = math.floor(oy / GRID_STEP_M) * GRID_STEP_M
            y_max = oy + gh_m
            y = y_min
            while y <= y_max:
                a = self._world_to_screen(ox, y)
                b = self._world_to_screen(ox + gw_m, y)
                p.drawLine(a, b)
                y += GRID_STEP_M
        elif self._x is not None:
            # Robot-centered fallback (existing behaviour preserved).
            x_min = math.floor((self._x - VIEW_HALF_M) / GRID_STEP_M) * GRID_STEP_M
            x_max = self._x + VIEW_HALF_M
            x = x_min
            while x <= x_max:
                a = self._world_to_screen(x, self._y - VIEW_HALF_M)
                b = self._world_to_screen(x, self._y + VIEW_HALF_M)
                p.drawLine(a, b)
                x += GRID_STEP_M
            y_min = math.floor((self._y - VIEW_HALF_M) / GRID_STEP_M) * GRID_STEP_M
            y_max = self._y + VIEW_HALF_M
            y = y_min
            while y <= y_max:
                a = self._world_to_screen(self._x - VIEW_HALF_M, y)
                b = self._world_to_screen(self._x + VIEW_HALF_M, y)
                p.drawLine(a, b)
                y += GRID_STEP_M
```

- [ ] **Step 5: Update the robot-arrow drawing to be transform-agnostic**

The existing arrow code (around lines 111–139) hand-computes screen offsets using the robot-centered convention. After auto-fit it must work in *both* modes. The cleanest fix: compute the arrow's three vertex positions in world coords and run each one through `_world_to_screen`. Then the arrow looks correct regardless of which transform is active.

Replace the arrow block (the section starting `# Robot arrow` through the end of the `if self._x is not None:` branch — but **keep the existing `else:` empty-state branch unchanged**) with:

```python
        # Robot arrow — direction = heading (yaw), length ROBOT_LEN_M in world.
        # All three vertices go through _world_to_screen so this is correct
        # in both auto-fit and robot-centered-fallback modes.
        if self._x is not None:
            tip_w = (self._x + ROBOT_LEN_M * math.cos(self._yaw),
                     self._y + ROBOT_LEN_M * math.sin(self._yaw))
            # Base centre is 0.4 lengths behind robot origin, along -heading.
            back = ROBOT_LEN_M * 0.4
            base_c_w = (self._x - back * math.cos(self._yaw),
                        self._y - back * math.sin(self._yaw))
            # Perpendicular offset (left/right of heading).
            perp_yaw = self._yaw + math.pi / 2
            half_w = ROBOT_LEN_M * 0.4
            base_l_w = (base_c_w[0] + half_w * math.cos(perp_yaw),
                        base_c_w[1] + half_w * math.sin(perp_yaw))
            base_r_w = (base_c_w[0] - half_w * math.cos(perp_yaw),
                        base_c_w[1] - half_w * math.sin(perp_yaw))
            tri = QPolygonF([
                self._world_to_screen(*tip_w),
                self._world_to_screen(*base_l_w),
                self._world_to_screen(*base_r_w),
            ])
            p.setPen(QPen(QColor("#ffffff"), 1))
            p.setBrush(QColor(ACCENT_BLUE))
            p.drawPolygon(tri)
```

(The `else:` empty-state branch — drawing "2D Map" big text and the "대기 중" hint — is left untouched here. Task 8 updates that hint string.)

- [ ] **Step 6: Run tests — expect PASS**

```bash
colcon build --packages-select pkrc_visualizer --symlink-install
colcon test --packages-select pkrc_visualizer --pytest-args -k test_topdown_map_widget -v
colcon test-result --verbose --test-result-base build/pkrc_visualizer
```

Expected: all 8 `test_topdown_map_widget` tests pass.

- [ ] **Step 7: Manual smoke test**

Run with live SLAM. Expected:
- Whole occupancy grid visible inside the panel (letterboxed if aspect mismatched).
- Robot arrow stays anchored to its real position as it moves.
- 1m grid lines align with grid origin.

- [ ] **Step 8: Commit**

```bash
git add src/pkrc_visualizer/pkrc_visualizer/pages/monitoring/topdown_map_widget.py \
        src/pkrc_visualizer/test/test_topdown_map_widget.py
git commit -m "feat(monitoring): auto-fit 2D map to grid bounds, north-up"
```

---

## Task 7: TF axes overlay (X red / Y green)

**Files:**
- Modify: `src/pkrc_visualizer/pkrc_visualizer/pages/monitoring/topdown_map_widget.py`

(Visual change only — verified manually.)

- [ ] **Step 1: Add `_paint_axes` helper**

In `_MapCanvas`, just above `paintEvent`, add:

```python
    def _paint_axes(self, p: QPainter) -> None:
        """Draw a small RViz-style coordinate triad at the robot pose.

        X axis red, Y axis green. Length = 0.5 m world (constant in metric
        units, so visual size scales with zoom). No labels — keep it terse.
        """
        if self._x is None:
            return
        AXIS_LEN_M = 0.5
        origin = self._world_to_screen(self._x, self._y)
        x_tip = self._world_to_screen(
            self._x + AXIS_LEN_M * math.cos(self._yaw),
            self._y + AXIS_LEN_M * math.sin(self._yaw))
        y_tip = self._world_to_screen(
            self._x + AXIS_LEN_M * math.cos(self._yaw + math.pi / 2),
            self._y + AXIS_LEN_M * math.sin(self._yaw + math.pi / 2))
        p.setPen(QPen(QColor(ACCENT_RED), 2))
        p.drawLine(origin, x_tip)
        p.setPen(QPen(QColor(ACCENT_GREEN), 2))
        p.drawLine(origin, y_tip)
```

- [ ] **Step 2: Wire it into paintEvent**

In `paintEvent`, call `self._paint_axes(p)` immediately before the robot-arrow block (so axes are drawn under the arrow tip but over the trail). Find this line:

```python
        # Robot arrow
```

Insert just above it:

```python
        # TF axes triad at robot pose (X red, Y green)
        self._paint_axes(p)
```

`ACCENT_RED` and `ACCENT_GREEN` are already imported via the `common.py` import block at the top of the file — verify they're listed:

```python
from pkrc_visualizer.pages.monitoring.common import (ACCENT_BLUE, ACCENT_CYAN,
                                                       PANEL_BG_INNER,
                                                       PANEL_BORDER, PANEL_QSS,
                                                       TEXT_DIM, TEXT_LABEL,
                                                       TEXT_PRIMARY, TITLE_QSS)
```

It's missing `ACCENT_RED` and `ACCENT_GREEN`. Update the import to:

```python
from pkrc_visualizer.pages.monitoring.common import (ACCENT_BLUE, ACCENT_CYAN,
                                                       ACCENT_GREEN, ACCENT_RED,
                                                       PANEL_BG_INNER,
                                                       PANEL_BORDER, PANEL_QSS,
                                                       TEXT_DIM, TEXT_LABEL,
                                                       TEXT_PRIMARY, TITLE_QSS)
```

- [ ] **Step 3: Build**

```bash
colcon build --packages-select pkrc_visualizer --symlink-install
```

Expected: clean build.

- [ ] **Step 4: Run existing test suite — expect PASS**

```bash
colcon test --packages-select pkrc_visualizer
colcon test-result --verbose --test-result-base build/pkrc_visualizer
```

Expected: no regressions.

- [ ] **Step 5: Manual smoke test**

Launch the visualizer with live SLAM. Expected: a small red (X) and green (Y) line emanate from the robot arrow's centre. Length stays consistent in world metres as the panel resizes.

- [ ] **Step 6: Commit**

```bash
git add src/pkrc_visualizer/pkrc_visualizer/pages/monitoring/topdown_map_widget.py
git commit -m "feat(monitoring): draw TF axes triad at robot pose on 2D map"
```

---

## Task 8: Empty-state text update

**Files:**
- Modify: `src/pkrc_visualizer/pkrc_visualizer/pages/monitoring/topdown_map_widget.py`

- [ ] **Step 1: Update the empty-state text**

In `paintEvent`, find the existing empty-state text (inside the `else:` branch around lines 145–149):

```python
            p.drawText(r.adjusted(0, 24, 0, 24), Qt.AlignCenter,
                       "/slam/fast_lio/odometry 대기 중")
```

Replace with:

```python
            p.drawText(r.adjusted(0, 24, 0, 24), Qt.AlignCenter,
                       "맵 대기 중\n(cartographer / fast_lio_loc)")
```

- [ ] **Step 2: Build and manually verify**

```bash
colcon build --packages-select pkrc_visualizer --symlink-install
source /home/hero/ros2_ws/install/setup.bash
ros2 launch pkrc_visualizer pkrc_visualizer.launch.py
```

Expected on first launch (no SLAM running): "2D Map" big text with "맵 대기 중\n(cartographer / fast_lio_loc)" below it.

- [ ] **Step 3: Commit**

```bash
git add src/pkrc_visualizer/pkrc_visualizer/pages/monitoring/topdown_map_widget.py
git commit -m "docs(monitoring): update 2D map empty-state hint to name both engines"
```

---

## Task 9: Version bump + CHANGELOG + README

**Files:**
- Modify: `src/pkrc_visualizer/setup.py`
- Modify: `src/pkrc_visualizer/package.xml`
- Modify: `src/pkrc_visualizer/CHANGELOG.md`
- Modify: `src/pkrc_visualizer/README.md` (only if user-facing description changes)

- [ ] **Step 1: Bump version 0.8.0 → 0.9.0**

In `src/pkrc_visualizer/setup.py` line 7:

```python
    version='0.9.0',
```

In `src/pkrc_visualizer/package.xml` line 5:

```xml
  <version>0.9.0</version>
```

- [ ] **Step 2: Add CHANGELOG entry**

Prepend a new entry above `## [0.8.0]` in `src/pkrc_visualizer/CHANGELOG.md`:

```markdown
## [0.9.0] — 2026-05-08 (minor)

### Added
- Monitoring 페이지의 "🗺 2D 맵" 패널이 occupancy grid를 직접 렌더링한다. Cartographer (`/slam/cartographer/map`)와 FastLIO localization (`/slam/fast_lio_loc/occupancy_grid`) 두 엔진을 병렬 구독, 운영 중인 엔진의 맵이 그대로 표시.
- 2D 맵 위에 RViz 스타일 TF 축 (X 빨강 / Y 초록, 0.5m world) + heading 화살표 + 30초 trail이 오버레이됨.
- 뷰는 occupancy grid bounds에 auto-fit (north-up, +x → screen right). 맵 종횡비 보존, 패널과 비율 안 맞으면 letterbox.
- Monitoring 페이지의 "소나 이미지" 패널이 polar 소나 영상을 표시 (기존 placeholder "TBD" 제거). m750d / m3000d 두 토픽 자동 감지: 도착하는 메시지가 있는 쪽이 화면을 차지.
- `topic_config.py`: `mon_map_carto`, `mon_map_fastlio`, `mon_sonar_m750d`, `mon_sonar_m3000d` TopicSpec 추가.
- 신규 위젯 `pages/monitoring/sonar_image_widget.py` — 기존 `widgets/image_view.ImageView`를 wrapping.

### Changed
- `pages/monitoring/topdown_map_widget.py`의 `_MapCanvas`가 occupancy grid layer + auto-fit + TF axes로 확장. 그리드가 없을 때는 기존 robot-centered 5m 뷰로 자동 fallback.
- Monitoring 페이지 dispatch 테이블의 `mon_odom`이 `_handle_odom`을 거쳐 `lookup_map_from_odom()`으로 odom→map 변환 후 위젯에 전달. TF 미준비 시 odom 좌표로 fallback (회귀 없음).

### Removed
- `pages/monitoring/sonar_placeholder_widget.py` (더 이상 import 안 됨).

### Verification
- `colcon test --packages-select pkrc_visualizer` 그린.
- 수동: Cartographer 라이브 → 맵 + 로봇 + 축 정상 표시.
- 수동: FastLIO localization 라이브 → 동일한 동작이 다른 토픽에서.
- 수동: SLAM 미가동 → "맵 대기 중" empty state.
- 수동: 소나 한쪽만 켜진 상황 / 둘 다 꺼진 상황 / 둘 다 켜진 상황 모두 의도한 대로.

### Notes
- TF lookup은 zero-timeout (`lookup_map_from_odom`이 이미 그렇게 구현됨). GUI thread 블로킹 없음.
```

- [ ] **Step 3: Update README user-facing section if needed**

Check `src/pkrc_visualizer/README.md` for any description of the Monitoring page that references "TBD" or the old empty placeholder. If found, update to describe the new live behaviour. If the README doesn't have such a section, no change needed.

```bash
grep -nE "(TBD|placeholder|2D 맵|소나)" src/pkrc_visualizer/README.md
```

If the search returns lines describing the old state, update them; otherwise skip.

- [ ] **Step 4: Final test run**

```bash
colcon build --packages-select pkrc_visualizer --symlink-install
colcon test --packages-select pkrc_visualizer
colcon test-result --verbose --test-result-base build/pkrc_visualizer
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/pkrc_visualizer/setup.py \
        src/pkrc_visualizer/package.xml \
        src/pkrc_visualizer/CHANGELOG.md \
        src/pkrc_visualizer/README.md
git commit -m "release(pkrc_visualizer): v0.9.0 — monitoring 2D map + sonar"
```

---

## Task 10: Open the pull request

- [ ] **Step 1: Push branch**

```bash
git push -u origin feat/monitoring-2dmap-sonar
```

- [ ] **Step 2: Create PR**

```bash
gh pr create --title "feat(pkrc_visualizer): live 2D map + sonar on Monitoring page" \
  --body "$(cat <<'EOF'
## Summary

- Replaces two placeholder panels on the Monitoring page with live ROS visualizations:
  - **2D Map**: occupancy grid from Cartographer or FastLIO localization (whichever runs), with TF axes, heading arrow, and 30s trail. Auto-fits to grid bounds.
  - **Sonar Image**: polar sonar image, auto-detect between m750d and m3000d.
- Robot pose lifted from odom → map via existing `lookup_map_from_odom()`.
- Bumps `pkrc_visualizer` to 0.9.0.

Spec: [docs/superpowers/specs/2026-05-08-monitoring-2dmap-sonar-design.md](docs/superpowers/specs/2026-05-08-monitoring-2dmap-sonar-design.md)
Plan: [docs/superpowers/plans/2026-05-08-monitoring-2dmap-sonar.md](docs/superpowers/plans/2026-05-08-monitoring-2dmap-sonar.md)

## Test plan

- [ ] `colcon test --packages-select pkrc_visualizer` green.
- [ ] Launch with Cartographer live → grid + robot + TF axes render; arrow tracks GPS-confirmed location.
- [ ] Launch with FastLIO localization live → same behaviour, different source topic.
- [ ] Kill SLAM → grid persists (last good); robot still moves; no crash.
- [ ] Both sonars on simultaneously → panel updates without crash; observe whether oscillation is acceptable in real ops (note: spec accepts this).
- [ ] Only m3000d on → m3000d displayed.
- [ ] Both sonars off → "소나 이미지 대기 중" hint visible.
- [ ] Resize window → 16:9 aspect lock holds; map letterboxes; sonar pixmap scales.
EOF
)"
```

Expected: PR URL printed.

---

## Self-review checklist

After every task: have you committed? Tests green? Manual smoke OK if applicable?

After Task 10: did the PR description list every manual smoke item?

If something feels off, stop and re-read the spec.

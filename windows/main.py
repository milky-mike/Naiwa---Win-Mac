"""Naiwa desktop pet for Windows 10/11. Uses original edited character assets.
Requires PySide6>=6.6. Run via start_windows.bat or build_windows.bat.
"""
import math
import os
import sys
import time
from collections import OrderedDict
from pathlib import Path

from PySide6.QtCore import QPoint, QRectF, QSettings, Qt, QTimer, QUrl
from PySide6.QtGui import QAction, QGuiApplication, QIcon, QMouseEvent, QPainter, QPixmap
from PySide6.QtMultimedia import QAudioOutput, QMediaPlayer
from PySide6.QtWidgets import QApplication, QMenu, QSystemTrayIcon, QWidget

from pet_state import PetState


def asset_root() -> Path:
    if getattr(sys, 'frozen', False):
        return Path(sys._MEIPASS) / 'assets'
    return Path(__file__).resolve().parent.parent / 'assets'


class DesktopNaiwa(QWidget):
    def __init__(self):
        super().__init__()
        self.root = asset_root()
        required = [self.root / 'Stills/pose_1.png', self.root / 'LaughFrames/frame_000.png', self.root / 'laugh_original_audio.m4a']
        missing = [str(p) for p in required if not p.is_file()]
        if missing:
            raise FileNotFoundError('Missing Naiwa assets: ' + ', '.join(missing))
        self.settings = QSettings('NaiwaDesktopPet', 'NaiwaPetWindows')
        self.scale = float(self.settings.value('scale', 0.65))
        self.volume = float(self.settings.value('volume', 0.75))
        self.muted = str(self.settings.value('muted', 'false')).lower() == 'true'
        self.repeats = int(self.settings.value('repeats', 3))
        self.belly_mode = str(self.settings.value('belly_mode', 'toggle'))
        if self.belly_mode not in ('toggle', 'auto'):
            self.belly_mode = 'toggle'
        self.scale = max(0.5, min(1.5, self.scale))
        self.repeats = self.repeats if self.repeats in (1, 3, 5) else 3
        self.state = PetState(now=time.monotonic(), belly_mode=self.belly_mode)
        self.current_key = ''
        self.current_pixmap = QPixmap()
        self.previous_pixmap = QPixmap()
        self.fade_started = 0.0
        self.fade_duration = 0.45
        self.is_fading = False
        self.cache = OrderedDict()
        self.drag_start = None
        self.window_at_drag_start = None
        self.dragging = False
        self.suppress_double_release = False
        self.hovered = False
        self._last_laugh_mode = False

        self.setWindowFlags(Qt.WindowType.FramelessWindowHint | Qt.WindowType.WindowStaysOnTopHint | Qt.WindowType.Tool)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setAttribute(Qt.WidgetAttribute.WA_NoSystemBackground)
        self.setMouseTracking(True)
        self.setWindowTitle('奶娃桌宠')
        self.setFixedSize(int(320 * self.scale), int(369 * self.scale))
        icon_path = self.root / 'AppIcon.png'
        self.setWindowIcon(QIcon(str(icon_path)))
        screen = QGuiApplication.primaryScreen().availableGeometry()
        saved_x, saved_y = self.settings.value('pos_x', None), self.settings.value('pos_y', None)
        if saved_x is not None and saved_y is not None:
            self.move(int(saved_x), int(saved_y))
        else:
            self.move(screen.right() - self.width() - 36, screen.bottom() - self.height() - 38)

        self.player = QMediaPlayer(self)
        self.audio_output = QAudioOutput(self)
        self.player.setAudioOutput(self.audio_output)
        self.player.setSource(QUrl.fromLocalFile(str(self.root / 'laugh_original_audio.m4a')))
        self.audio_output.setVolume(0 if self.muted else self.volume)
        self.player.errorOccurred.connect(self._audio_error)

        self.single_click_timer = QTimer(self)
        self.single_click_timer.setSingleShot(True)
        self.single_click_timer.timeout.connect(self.single_click)

        self.tray = QSystemTrayIcon(QIcon(str(icon_path)), self)
        self.tray.setToolTip('奶娃桌宠 · 右键设置')
        self.tray.activated.connect(self._tray_activated)
        self.refresh_menu()
        self.tray.show()

        self.refresh_image(time.monotonic())
        self.clock = QTimer(self)
        self.clock.setTimerType(Qt.TimerType.PreciseTimer)
        self.clock.timeout.connect(self.tick)
        self.clock.start(33)

    def _audio_error(self, error, message):
        if message:
            print('Audio playback warning:', message, file=sys.stderr)

    def pixmap(self, key: str) -> QPixmap:
        if key in self.cache:
            pm = self.cache.pop(key)
            self.cache[key] = pm
            return pm
        pm = QPixmap(str(self.root / key))
        self.cache[key] = pm
        # Original 720x830 RGBA files cost about 2.4MB each; bound RAM use.
        while len(self.cache) > 52:
            self.cache.popitem(last=False)
        return pm

    def refresh_image(self, now: float):
        key = self.state.image_key(now)
        if key != self.current_key:
            pm = self.pixmap(key)
            if not pm.isNull():
                # Smooth only transitions between STILL poses. Never crossfade
                # live animation frames: doing so caused the blurry veil in V3.
                fade = (self.current_key.startswith('Stills/') and
                        key.startswith('Stills/') and not self.current_pixmap.isNull())
                self.previous_pixmap = self.current_pixmap if fade else QPixmap()
                self.is_fading = fade
                self.fade_started = now
                self.current_pixmap = pm
                self.current_key = key
                self.update()
        elif self.is_fading or (self.hovered and self.state.mode == 'cycle'):
            self.update()

    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform, True)
        p.setRenderHint(QPainter.RenderHint.Antialiasing, True)
        if not self.current_pixmap.isNull():
            now = time.monotonic()
            lift = math.sin(now * 4.5) * 1.2 if (self.hovered and self.state.mode == 'cycle') else 0.0
            dest = QRectF(0, lift, self.width(), self.height())
            if self.is_fading and not self.previous_pixmap.isNull():
                fraction = min(1.0, max(0.0, (now - self.fade_started) / self.fade_duration))
                if fraction < 1.0:
                    p.setOpacity(1.0 - fraction)
                    p.drawPixmap(dest, self.previous_pixmap, QRectF(self.previous_pixmap.rect()))
                    p.setOpacity(fraction)
                    p.drawPixmap(dest, self.current_pixmap, QRectF(self.current_pixmap.rect()))
                    p.setOpacity(1.0)
                else:
                    self.is_fading = False
                    self.previous_pixmap = QPixmap()
                    p.drawPixmap(dest, self.current_pixmap, QRectF(self.current_pixmap.rect()))
            else:
                p.drawPixmap(dest, self.current_pixmap, QRectF(self.current_pixmap.rect()))
        p.end()

    def tick(self):
        now = time.monotonic()
        was_laughing = self.state.mode == 'laugh'
        self.state.tick(now)
        if was_laughing and self.state.mode != 'laugh':
            self.player.stop()
        self.refresh_image(now)

    def single_click(self):
        now = time.monotonic()
        if self.state.mode == 'laugh':
            self.player.stop()
        self.state.click(now)
        self.refresh_image(now)

    def double_click(self):
        self.single_click_timer.stop()
        self.state.start_laugh(time.monotonic(), self.repeats)
        self.audio_output.setVolume(0 if self.muted else self.volume)
        self.player.stop()
        self.player.setLoops(self.repeats)
        self.player.play()
        self.refresh_image(time.monotonic())

    def resume_cycle(self, advance=False):
        self.single_click_timer.stop()
        self.player.stop()
        self.state.resume(time.monotonic(), advance=advance)
        self.refresh_image(time.monotonic())

    def stop_laugh(self):
        now = time.monotonic()
        self.player.stop()
        self.state.finish_laugh(now)
        self.refresh_image(now)

    def enterEvent(self, event):
        self.hovered = True
        super().enterEvent(event)

    def leaveEvent(self, event):
        self.hovered = False
        super().leaveEvent(event)

    def mousePressEvent(self, event: QMouseEvent):
        if event.button() == Qt.MouseButton.LeftButton:
            self.drag_start = event.globalPosition().toPoint()
            self.window_at_drag_start = self.pos()
            self.dragging = False
            event.accept()
        else:
            super().mousePressEvent(event)

    def mouseMoveEvent(self, event: QMouseEvent):
        if self.drag_start is not None and event.buttons() & Qt.MouseButton.LeftButton:
            displacement = event.globalPosition().toPoint() - self.drag_start
            if displacement.manhattanLength() >= 5:
                self.dragging = True
                self.single_click_timer.stop()
                self.move(self.window_at_drag_start + displacement)
                event.accept()
                return
        super().mouseMoveEvent(event)

    def mouseDoubleClickEvent(self, event: QMouseEvent):
        if event.button() == Qt.MouseButton.LeftButton:
            self.suppress_double_release = True
            self.double_click()
            event.accept()
        else:
            super().mouseDoubleClickEvent(event)

    def mouseReleaseEvent(self, event: QMouseEvent):
        if event.button() == Qt.MouseButton.LeftButton:
            self.drag_start = None
            if self.dragging:
                self.dragging = False
                self.settings.setValue('pos_x', self.pos().x())
                self.settings.setValue('pos_y', self.pos().y())
            elif self.suppress_double_release:
                self.suppress_double_release = False
            else:
                # Wait briefly before dispatching a single click, so a quick
                # double click plays the video WITHOUT enlarging the belly first.
                self.single_click_timer.start(QApplication.doubleClickInterval() + 35)
            event.accept()
        else:
            super().mouseReleaseEvent(event)

    def contextMenuEvent(self, event):
        self.make_menu().exec(event.globalPos())

    def _tray_activated(self, reason):
        if reason == QSystemTrayIcon.ActivationReason.Trigger:
            self.show()
            self.raise_()

    def make_menu(self):
        menu = QMenu('奶娃桌宠', self)
        menu.addAction('双击动作：捧腹大笑（原声）', self.double_click)
        menu.addAction('停止大笑', self.stop_laugh)
        menu.addAction('回到第一张托腮（自动轮换）', lambda: self.resume_cycle(False))
        menu.addAction('立刻下一姿势', lambda: self.resume_cycle(True))
        menu.addSeparator()
        belly_menu = menu.addMenu('肚子点击模式')
        for label, behavior in [('交替变大 / 变小（默认）', 'toggle'), ('单击自动变大再缩回', 'auto')]:
            item = belly_menu.addAction(label)
            item.setCheckable(True)
            item.setChecked(self.belly_mode == behavior)
            item.triggered.connect(lambda _, b=behavior: self.set_belly_mode(b))
        menu.addSeparator()
        mute_action = menu.addAction('取消静音' if self.muted else '静音')
        mute_action.triggered.connect(self.toggle_mute)
        volumes = menu.addMenu('声音大小')
        for v in [25, 50, 75, 100]:
            item = volumes.addAction(f'{v}%')
            item.setCheckable(True)
            item.setChecked(abs(self.volume*100-v)<1)
            item.triggered.connect(lambda _, v=v: self.set_volume(v))
        loops = menu.addMenu('双击播放次数')
        for n in [1, 3, 5]:
            item = loops.addAction(f'{n} 遍 · 约 {n * 14.8:.0f} 秒')
            item.setCheckable(True)
            item.setChecked(self.repeats == n)
            item.triggered.connect(lambda _, n=n: self.set_repeats(n))
        sizes = menu.addMenu('桌宠大小')
        for n in [50, 65, 75, 100, 125, 150]:
            item = sizes.addAction(f'{n}%')
            item.setCheckable(True)
            item.setChecked(abs(self.scale*100-n)<1)
            item.triggered.connect(lambda _, n=n: self.set_size(n))
        menu.addSeparator()
        menu.addAction('退出奶娃', self.quit_app)
        return menu

    def refresh_menu(self):
        self.tray.setContextMenu(self.make_menu())

    def set_belly_mode(self, behavior):
        self.belly_mode = behavior
        self.settings.setValue('belly_mode', behavior)
        self.state.set_belly_mode(behavior, time.monotonic())
        self.refresh_image(time.monotonic())
        self.refresh_menu()

    def toggle_mute(self):
        self.muted = not self.muted
        self.settings.setValue('muted', self.muted)
        self.audio_output.setVolume(0 if self.muted else self.volume)
        self.refresh_menu()

    def set_volume(self, n):
        self.volume = n/100.0
        self.settings.setValue('volume', self.volume)
        self.audio_output.setVolume(0 if self.muted else self.volume)
        self.refresh_menu()

    def set_repeats(self, n):
        self.repeats = n
        self.settings.setValue('repeats', n)
        self.refresh_menu()

    def set_size(self, n):
        self.scale = n/100.0
        self.settings.setValue('scale', self.scale)
        self.setFixedSize(int(320*self.scale), int(369*self.scale))
        self.refresh_menu()

    def quit_app(self):
        self.player.stop()
        self.tray.hide()
        QApplication.instance().quit()

    def closeEvent(self, event):
        self.quit_app()
        event.accept()


def main():
    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)
    widget = DesktopNaiwa()
    widget.show()
    sys.exit(app.exec())


if __name__ == '__main__':
    main()

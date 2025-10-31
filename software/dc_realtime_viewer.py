#!/usr/bin/env python3
"""
Digital Capture Oscilloscope Viewer
-----------------------------------
Streams the FPGA digital capture bytes (EP3) and plots the eight channels
using a Matplotlib oscilloscope-style display. The USB command/streaming
sequence mirrors software/diagnose_dc.py; the GUI logic is inspired by
software/adc_stream_viewer.py and software/wave_display.py.

Controls (on the Matplotlib figure):
    - "开始": start streaming with the selected sample rate
    - "停止": stop streaming immediately
    - Sample-rate radio buttons: choose the divider used in the START command

Requirements:
    pip install pyusb matplotlib numpy
"""

import sys
import time
import threading
import queue
from collections import deque
from typing import List

import numpy as np
import usb.core
import usb.util

import matplotlib.pyplot as plt
from matplotlib.animation import FuncAnimation
from matplotlib.widgets import Button, RadioButtons


USB_VID = 0x33AA
USB_PID = 0x0000

EP_CTRL_OUT = 0x02
EP_DC_IN = 0x83

STOP_CMD = bytes([0xAA, 0x55, 0x0C, 0x00, 0x00, 0x0C])

SAMPLE_RATE_OPTIONS = [
    ("1 kHz", 1_000),
    ("2 kHz", 2_000),
    ("5 kHz", 5_000),
    ("10 kHz", 10_000),
    ("20 kHz", 20_000),
    ("50 kHz", 50_000),
    ("100 kHz", 100_000),
    ("200 kHz", 200_000),
    ("400 kHz", 400_000),
    ("500 kHz", 500_000),
    ("600 kHz", 600_000),
    ("1 MHz", 1_000_000),
    ("2 MHz", 2_000_000),
    ("5 MHz", 5_000_000),
    ("10 MHz", 10_000_000),
    ("20 MHz", 20_000_000),
    ("30 MHz", 30_000_000),
]
DEFAULT_SAMPLE_RATE = 100_000

WINDOW_SAMPLES = 4096  # samples per channel displayed
READ_SIZE = 32768
QUEUE_MAX = 8192

try:
    LOOKUP_TABLE = np.unpackbits(
        np.arange(256, dtype=np.uint8)[:, None], axis=1, bitorder="little"
    )
except TypeError:
    LOOKUP_TABLE = np.unpackbits(
        np.arange(256, dtype=np.uint8)[:, None], axis=1
    )[:, ::-1]


def generate_start_frame(sample_rate_hz: int) -> bytes:
    divider = 60_000_000 // max(sample_rate_hz, 1)
    div_h = (divider >> 8) & 0xFF
    div_l = divider & 0xFF
    cmd = 0x0B
    checksum = (cmd + 0x00 + 0x02 + div_h + div_l) & 0xFF
    return bytes([0xAA, 0x55, cmd, 0x00, 0x02, div_h, div_l, checksum])


class DcUsbInterface:
    """USB transport identical to diagnose_dc.py (STOP->START sequencing)."""

    def __init__(self):
        self.dev = None

    def _get_backends(self):
        backends = []
        try:
            import usb.backend.libusb1  # type: ignore  # noqa

            backend = usb.backend.libusb1.get_backend()
            if backend:
                backends.append(backend)
        except Exception:
            pass
        try:
            import usb.backend.libusb0  # type: ignore  # noqa

            backend = usb.backend.libusb0.get_backend()
            if backend:
                backends.append(backend)
        except Exception:
            pass
        try:
            import usb.backend.openusb  # type: ignore  # noqa

            backend = usb.backend.openusb.get_backend()
            if backend:
                backends.append(backend)
        except Exception:
            pass

        if not backends:
            backends.append(None)
        return backends

    def open(self):
        for backend in self._get_backends():
            try:
                dev = usb.core.find(idVendor=USB_VID, idProduct=USB_PID, backend=backend)
                if dev:
                    self.dev = dev
                    break
            except Exception:
                continue

        if not self.dev:
            raise RuntimeError("Unable to locate FPGA USB device")

        if hasattr(self.dev, "is_kernel_driver_active"):
            try:
                if self.dev.is_kernel_driver_active(0):
                    self.dev.detach_kernel_driver(0)
            except (NotImplementedError, AttributeError, usb.core.USBError):
                pass

        try:
            self.dev.set_configuration()
        except usb.core.USBError:
            pass

    def start_capture(self, sample_rate_hz: int):
        if not self.dev:
            raise RuntimeError("Device not opened")

        self.dev.write(EP_CTRL_OUT, STOP_CMD)
        time.sleep(0.05)
        self.dev.write(EP_CTRL_OUT, generate_start_frame(sample_rate_hz))

    def stop_capture(self):
        if self.dev:
            try:
                self.dev.write(EP_CTRL_OUT, STOP_CMD)
            except usb.core.USBError:
                pass

    def read(self, size: int, timeout_ms: int = 10) -> bytes:
        if not self.dev:
            raise RuntimeError("Device not opened")
        try:
            data = self.dev.read(EP_DC_IN, size, timeout=timeout_ms)
            return bytes(data)
        except usb.core.USBError as exc:
            errno = getattr(exc, "errno", None)
            if errno in (110, 116, None) or "timed out" in str(exc).lower():
                return b""
            raise

    def close(self):
        self.stop_capture()
        if self.dev:
            usb.util.dispose_resources(self.dev)
            self.dev = None


class UsbStreamWorker(threading.Thread):
    """Continuously drains EP3 into a queue when running_flag is set.
    Coalesces small USB reads into larger buffers to reduce queue pressure,
    and tracks dropped-chunk count for diagnostics.
    """

    def __init__(self, iface: DcUsbInterface, data_queue: queue.Queue):
        super().__init__(daemon=True)
        self.iface = iface
        self.data_queue = data_queue
        self.running_flag = threading.Event()
        self.stop_flag = threading.Event()
        # Diagnostics / flow control stats
        self.drop_count = 0
        self.bytes_pushed = 0
        # Coalescing parameters: try to push ~256KB at a time or every 10ms
        self._coal_target = 256 * 1024
        self._coal_time_s = 0.010

    def start_stream(self):
        self.running_flag.set()
        if not self.is_alive():
            self.start()

    def stop_stream(self):
        self.running_flag.clear()

    def stop_worker(self):
        self.stop_flag.set()
        self.running_flag.clear()

    def run(self):
        buf = bytearray()
        last_flush = time.time()
        while not self.stop_flag.is_set():
            if not self.running_flag.is_set():
                time.sleep(0.05)
                # Reset coalescer between runs to reduce latency on restart
                if buf:
                    try:
                        self.data_queue.put(bytes(buf), timeout=0.1)
                        self.bytes_pushed += len(buf)
                    except queue.Full:
                        self.drop_count += 1
                    buf.clear()
                last_flush = time.time()
                continue

            try:
                chunk = self.iface.read(READ_SIZE, timeout_ms=10)
            except Exception as exc:
                # Push exception downstream for status display
                try:
                    self.data_queue.put(exc, timeout=0.1)
                except queue.Full:
                    self.drop_count += 1
                time.sleep(0.02)
                continue

            if chunk:
                buf.extend(chunk)

            now = time.time()
            if len(buf) >= self._coal_target or (buf and (now - last_flush) >= self._coal_time_s):
                try:
                    self.data_queue.put(bytes(buf), timeout=0.02)
                    self.bytes_pushed += len(buf)
                except queue.Full:
                    # Drop coalesced data if GUI cannot keep up
                    self.drop_count += 1
                buf.clear()
                last_flush = now
class DigitalCaptureViewer:
    """Matplotlib oscilloscope-style display for eight digital channels."""

    def __init__(self):
        self.iface = DcUsbInterface()
        self.iface.open()

        self.data_queue: queue.Queue = queue.Queue(maxsize=QUEUE_MAX)
        self.worker = UsbStreamWorker(self.iface, self.data_queue)

        self.default_rate_index = next(
            (idx for idx, (_, value) in enumerate(SAMPLE_RATE_OPTIONS) if value == DEFAULT_SAMPLE_RATE),
            0,
        )
        self.current_rate = SAMPLE_RATE_OPTIONS[self.default_rate_index][1]
        self.capture_active = False
        self.last_error = None
        self.last_data_time = 0.0

        self.buffer = np.zeros((8, WINDOW_SAMPLES), dtype=np.uint8)
        self.valid_samples = 0
        self.total_samples = 0
        self.write_pos = 0

        self.fig, self.ax = plt.subplots(figsize=(12, 6))
        self.ax.set_title("Digital Capture Waveforms")
        self.ax.set_xlabel("Sample Index")
        self.ax.set_ylabel("Logic Level")
        self.ax.set_xlim(0, WINDOW_SAMPLES)
        self.ax.set_ylim(-1, 8)
        self.ax.set_yticks(range(8))
        self.ax.grid(True, alpha=0.3)

        self.lines = [
            self.ax.plot([], [], drawstyle="steps-post", linewidth=1.0)[0]
            for _ in range(8)
        ]

        self.status_text = self.ax.text(
            0.01,
            0.96,
            "停止",
            transform=self.ax.transAxes,
            fontsize=10,
            color="tab:gray",
        )

        self._build_controls()
        self.animation = FuncAnimation(self.fig, self._update_plot, interval=50, blit=False)

        self.fig.canvas.mpl_connect("close_event", self._handle_close)

    def _build_controls(self):
        plt.subplots_adjust(left=0.08, right=0.82, bottom=0.18, top=0.92)

        ax_start = plt.axes([0.84, 0.82, 0.12, 0.08])
        ax_stop = plt.axes([0.84, 0.70, 0.12, 0.08])
        self.btn_start = Button(ax_start, "开始")
        self.btn_stop = Button(ax_stop, "停止")
        self.btn_start.on_clicked(lambda _: self.start_stream())
        self.btn_stop.on_clicked(lambda _: self.stop_stream())

        ax_radio = plt.axes([0.84, 0.30, 0.12, 0.36])
        labels = [name for name, _ in SAMPLE_RATE_OPTIONS]
        self.radio_rates = RadioButtons(ax_radio, labels, active=self.default_rate_index)

        def _on_rate(label: str):
            for name, value in SAMPLE_RATE_OPTIONS:
                if name == label:
                    self.current_rate = value
                    break
            self.status_text.set_text(f"采样率: {self.current_rate/1000:.0f} kHz")
            if self.capture_active:
                self.start_stream()

        self.radio_rates.on_clicked(_on_rate)

    def start_stream(self):
        try:
            self.capture_active = False
            self.worker.stop_stream()
            self.iface.stop_capture()
            time.sleep(0.05)
            self._flush_queue()
            self._clear_buffers()

            self.worker.start_stream()
            self.iface.start_capture(self.current_rate)

            if self.current_rate > 200_000:
                settle_time = 1.5
                flush_interval = 0.02
            else:
                settle_time = max(0.2, 10.0 / self.current_rate)
                flush_interval = 0.05

            settle_deadline = time.time() + settle_time
            while time.time() < settle_deadline:
                self._flush_queue()
                time.sleep(flush_interval)

            self._clear_buffers()
            self._flush_queue()
            self.last_error = None
            self.last_data_time = time.time()
            self.capture_active = True
            self.status_text.set_text("采集中…")
            self.status_text.set_color("tab:green")
        except Exception as exc:
            self.capture_active = False
            self.status_text.set_text(f"错误: {exc}")
            self.status_text.set_color("tab:red")

    def stop_stream(self):
        self.capture_active = False
        self.worker.stop_stream()
        self.iface.stop_capture()
        self._flush_queue()
        self.status_text.set_text("停止")
        self.status_text.set_color("tab:gray")

    def _clear_buffers(self):
        self.buffer.fill(0)
        self.valid_samples = 0
        self.total_samples = 0
        self.write_pos = 0
        self.last_data_time = 0.0
        for line in self.lines:
            line.set_data([], [])

    def _update_plot(self, _):
        self._drain_queue()

        if self.capture_active and self.last_error:
            self.status_text.set_text(f"USB错误: {self.last_error}")
            self.status_text.set_color("tab:red")
        elif self.capture_active and (time.time() - self.last_data_time > 0.6):
            self.status_text.set_text("等待数据…")
            self.status_text.set_color("tab:orange")
        elif not self.capture_active and self.valid_samples == 0:
            self.status_text.set_text("停止")
            self.status_text.set_color("tab:gray")

        if self.valid_samples == 0:
            return self.lines

        samples = self.valid_samples
        x = np.arange(samples)

        if samples < WINDOW_SAMPLES:
            ordered = self.buffer[:, :samples]
        else:
            start = self.write_pos % WINDOW_SAMPLES
            ordered = np.concatenate(
                (self.buffer[:, start:], self.buffer[:, :start]), axis=1
            )
        for idx in range(8):
            y = ordered[idx, :samples] + idx
            self.lines[idx].set_data(x, y)

        if self.capture_active:
            self.ax.set_xlim(0, max(samples, WINDOW_SAMPLES))
        if self.capture_active and self.last_error is None:
            self.status_text.set_text(f"RUN: {self.total_samples} pts  drops={self.worker.drop_count}")
            self.status_text.set_color("tab:green")
        elif not self.capture_active and self.valid_samples > 0:
            self.status_text.set_text("停止")
            self.status_text.set_color("tab:gray")
        return self.lines

    def _drain_queue(self):
        while True:
            try:
                item = self.data_queue.get_nowait()
            except queue.Empty:
                break

            if isinstance(item, Exception):
                self.last_error = item
                continue

            self._append_samples(item)

    def _append_samples(self, chunk: bytes):
        byte_array = np.frombuffer(chunk, dtype=np.uint8)
        bits = LOOKUP_TABLE[byte_array]  # shape (N, 8)
        num_samples = bits.shape[0]

        if num_samples >= WINDOW_SAMPLES:
            self.buffer[:] = bits[-WINDOW_SAMPLES:].T
            self.valid_samples = WINDOW_SAMPLES
            self.write_pos = 0
        else:
            end_pos = self.write_pos + num_samples
            if end_pos <= WINDOW_SAMPLES:
                self.buffer[:, self.write_pos:end_pos] = bits.T
            else:
                first = WINDOW_SAMPLES - self.write_pos
                self.buffer[:, self.write_pos:] = bits[:first].T
                remainder = num_samples - first
                self.buffer[:, :remainder] = bits[first:].T
            self.write_pos = (self.write_pos + num_samples) % WINDOW_SAMPLES
            self.valid_samples = min(WINDOW_SAMPLES, self.valid_samples + num_samples)

        self.total_samples += num_samples
        self.last_data_time = time.time()

    def _flush_queue(self):
        while True:
            try:
                self.data_queue.get_nowait()
            except queue.Empty:
                break

    def _handle_close(self, _event):
        self.stop_stream()
        self.worker.stop_worker()
        self.iface.close()

    def show(self):
        plt.show()


def main():
    try:
        viewer = DigitalCaptureViewer()
    except Exception as exc:
        print(f"初始化失败: {exc}")
        sys.exit(1)

    viewer.show()


if __name__ == "__main__":
    main()

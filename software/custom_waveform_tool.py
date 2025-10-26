#!/usr/bin/env python3
"""Custom waveform uploader for dual-channel DAC with optional loop playback."""

import argparse
import struct
import sys
import time

import numpy as np
import serial
from PySide6 import QtCore, QtGui, QtWidgets


CUSTOM_WAVEFORM_CMD = 0xFC
FRAME_HEADER = [0xAA, 0x55]
DAC_CLOCK_FREQ = 120_000_000  # 120MHz DAC clock

LOOP_ENABLE = 0x04
CHANNEL_B = 0x08  # Bit[3] selects channel: 0=A, 1=B

DAC_MIN = 0x0000
DAC_MAX = 0x3FFF
DAC_MID = 0x2000
DAC_BITS = 14

MAX_WAVEFORM_LENGTH = 256  # Two independent 256-entry SDPBs (uses 1024-depth SDPB, only 0-255 used)
DEFAULT_FREQ_HZ = 1000.0
DEFAULT_GUI_SAMPLES = 256  # Can use up to 256 samples
DEFAULT_SAMPLE_RATE_HZ = DEFAULT_FREQ_HZ * DEFAULT_GUI_SAMPLES


def calculate_checksum(data):
    return sum(data) & 0xFF


def calculate_sample_rate_word(waveform_length, output_freq_hz, dac_clock_hz=DAC_CLOCK_FREQ):
    playback_freq = output_freq_hz * waveform_length
    return calculate_sample_rate_word_from_rate(playback_freq, dac_clock_hz=dac_clock_hz)


def calculate_sample_rate_word_from_rate(sample_rate_hz, dac_clock_hz=DAC_CLOCK_FREQ):
    if sample_rate_hz <= 0:
        raise ValueError("Sample rate must be positive")
    # DDS phase accumulator is 32-bit, address extracted from phase[31:24] (8-bit for 256 entries)
    # Since FPGA extracts address from phase[31:24], we use 2^24 not 2^32
    # Correct formula: rate_word = (sample_rate_hz × 2^24) / dac_clock_hz
    rate_word = int(round((sample_rate_hz * (2**24)) / dac_clock_hz))
    return max(rate_word, 1)


def normalize_to_dac(samples):
    samples = np.clip(samples, -1.0, 1.0)
    scale = (DAC_MAX - 1) / 2.0
    dac_values = np.rint(samples * scale + DAC_MID).astype(np.int32)
    return np.clip(dac_values, DAC_MIN, DAC_MAX).astype(np.uint16)


def pack_sample_to_bytes(sample_value):
    sample_value = int(sample_value) & 0x3FFF
    low_byte = sample_value & 0xFF
    high_byte = (sample_value >> 8) & 0xFF
    return [low_byte, high_byte]


def generate_waveform_frame(control_byte, waveform_length, sample_rate_word, waveform_data):
    frame = []
    frame.extend(FRAME_HEADER)
    frame.append(CUSTOM_WAVEFORM_CMD)

    data_len = 7 + waveform_length * 2
    frame.append((data_len >> 8) & 0xFF)
    frame.append(data_len & 0xFF)

    frame.append(control_byte)
    frame.append((waveform_length >> 8) & 0xFF)
    frame.append(waveform_length & 0xFF)
    frame.extend(struct.pack('>I', sample_rate_word))

    for sample in waveform_data:
        frame.extend(pack_sample_to_bytes(sample))

    checksum = calculate_checksum(frame[2:])
    frame.append(checksum)

    return frame


def build_single_packet(waveform_data, sample_rate_word, loop_mode=False, channel='A'):
    waveform_length = len(waveform_data)

    if waveform_length == 0:
        raise ValueError("Waveform is empty")
    if waveform_length > MAX_WAVEFORM_LENGTH:
        raise ValueError(f"Waveform length {waveform_length} exceeds {MAX_WAVEFORM_LENGTH}")

    control = 0x00
    if loop_mode:
        control |= LOOP_ENABLE
    if channel.upper() == 'B':
        control |= CHANNEL_B

    return generate_waveform_frame(control, waveform_length, sample_rate_word, waveform_data)


def load_waveform_from_file(file_path):
    try:
        data = np.loadtxt(file_path, delimiter=',')
        data = np.atleast_1d(data)

        if np.any(np.isnan(data)):
            raise ValueError("File contains NaN")

        if np.all((data >= DAC_MIN) & (data <= DAC_MAX)) and np.allclose(data, np.round(data)):
            # Already 14-bit integer samples; convert back to [-1, 1] for editing/export pipeline
            scale = (DAC_MAX - 1) / 2.0
            data = ((data - DAC_MID) / scale).astype(np.float64)
            data = np.clip(data, -1.0, 1.0)
        else:
            # Assume normalized float data
            data = np.clip(data, -1.0, 1.0)

        return data
    except Exception as exc:
        raise ValueError(f"Failed to load waveform from {file_path}: {exc}") from exc


def send_packet_via_serial(packet, port, baudrate=115200):
    try:
        with serial.Serial(port, baudrate, timeout=2) as ser:
            time.sleep(0.1)
            ser.write(bytes(packet))
        print("Successfully sent waveform packet")
    except serial.SerialException as exc:
        raise RuntimeError(f"Serial communication error: {exc}") from exc


class WaveformCanvas(QtWidgets.QWidget):
    samples_changed = QtCore.Signal()

    def __init__(self, parent=None, num_samples=DEFAULT_GUI_SAMPLES):
        super().__init__(parent)
        self.setMinimumHeight(240)
        self.setMouseTracking(True)
        self._samples = np.zeros(num_samples, dtype=np.float64)
        self._drawing = False

    def sample_count(self):
        return len(self._samples)

    def samples(self):
        return self._samples

    def set_samples(self, samples: np.ndarray):
        self._samples = samples
        self.update()
        self.samples_changed.emit()

    def clear(self):
        self._samples.fill(0.0)
        self.update()
        self.samples_changed.emit()

    def set_sample_value(self, index: int, value: float):
        if 0 <= index < len(self._samples):
            self._samples[index] = np.clip(value, -1.0, 1.0)
            self.update()
            self.samples_changed.emit()

    def paintEvent(self, event: QtGui.QPaintEvent) -> None:
        painter = QtGui.QPainter(self)
        painter.fillRect(self.rect(), QtGui.QColor("#ffffff"))
        painter.setRenderHint(QtGui.QPainter.Antialiasing, True)

        width = self.width()
        height = self.height()

        # Draw axes
        axis_pen = QtGui.QPen(QtGui.QColor("#cccccc"))
        axis_pen.setWidth(1)
        painter.setPen(axis_pen)
        painter.drawLine(0, height // 2, width, height // 2)
        painter.drawRect(0, 0, width - 1, height - 1)

        if len(self._samples) < 2:
            return

        path = QtGui.QPainterPath()
        for idx, sample in enumerate(self._samples):
            x = (idx / (len(self._samples) - 1)) * width
            norm = (sample + 1.0) / 2.0  # 0 .. 1
            y = (1.0 - norm) * height
            if idx == 0:
                path.moveTo(x, y)
            else:
                path.lineTo(x, y)

        painter.setPen(QtGui.QPen(QtGui.QColor("#007acc"), 2))
        painter.drawPath(path)

    def mousePressEvent(self, event: QtGui.QMouseEvent) -> None:
        if event.button() == QtCore.Qt.LeftButton:
            self._drawing = True
            self._apply_mouse_event(event.position())

    def mouseMoveEvent(self, event: QtGui.QMouseEvent) -> None:
        if self._drawing:
            self._apply_mouse_event(event.position())

    def mouseReleaseEvent(self, event: QtGui.QMouseEvent) -> None:
        if event.button() == QtCore.Qt.LeftButton:
            self._drawing = False

    def _apply_mouse_event(self, pos: QtCore.QPointF) -> None:
        width = max(self.width(), 1)
        height = max(self.height(), 1)
        idx = int(np.clip(round((pos.x() / width) * (len(self._samples) - 1)), 0, len(self._samples) - 1))
        value = 1.0 - 2.0 * np.clip(pos.y() / height, 0.0, 1.0)
        self._samples[idx] = np.clip(value, -1.0, 1.0)
        self.update()
        self.samples_changed.emit()


class WaveformEditorWindow(QtWidgets.QMainWindow):
    def __init__(self, serial_port: str | None = None):
        super().__init__()
        self.setWindowTitle("Custom Waveform Editor")
        self.resize(900, 600)

        self.samples = np.zeros(DEFAULT_GUI_SAMPLES, dtype=np.float64)

        central = QtWidgets.QWidget(self)
        self.setCentralWidget(central)

        main_layout = QtWidgets.QVBoxLayout(central)

        self.canvas = WaveformCanvas(num_samples=len(self.samples))
        self.canvas.set_samples(self.samples)
        main_layout.addWidget(self.canvas, stretch=1)

        form_layout = QtWidgets.QGridLayout()
        main_layout.addLayout(form_layout)

        self.freq_input = QtWidgets.QDoubleSpinBox()
        self.freq_input.setRange(1.0, 200_000.0)
        self.freq_input.setValue(DEFAULT_FREQ_HZ)
        self.freq_input.setSuffix(" Hz")
        form_layout.addWidget(QtWidgets.QLabel("Waveform Frequency:"), 0, 0)
        form_layout.addWidget(self.freq_input, 0, 1)

        self.sample_rate_input = QtWidgets.QDoubleSpinBox()
        self.sample_rate_input.setRange(1_000.0, 50_000_000.0)
        default_sample_rate = max(DEFAULT_SAMPLE_RATE_HZ, self.freq_input.value() * len(self.samples))
        self.sample_rate_input.setValue(default_sample_rate)
        self.sample_rate_input.setSuffix(" Hz")
        form_layout.addWidget(QtWidgets.QLabel("Playback Sample Rate:"), 0, 2)
        form_layout.addWidget(self.sample_rate_input, 0, 3)

        self.loop_checkbox = QtWidgets.QCheckBox("Loop playback")
        self.loop_checkbox.setChecked(True)
        form_layout.addWidget(self.loop_checkbox, 0, 4)

        self.channel_combo = QtWidgets.QComboBox()
        self.channel_combo.addItems(['Channel A', 'Channel B'])
        form_layout.addWidget(QtWidgets.QLabel("DAC Channel:"), 0, 5)
        form_layout.addWidget(self.channel_combo, 0, 6)

        self.port_input = QtWidgets.QLineEdit()
        self.port_input.setPlaceholderText("COM3 or /dev/ttyUSB0")
        if serial_port:
            self.port_input.setText(serial_port)
        form_layout.addWidget(QtWidgets.QLabel("Serial Port:"), 1, 0)
        form_layout.addWidget(self.port_input, 1, 1)

        button_layout = QtWidgets.QHBoxLayout()
        main_layout.addLayout(button_layout)

        self.clear_button = QtWidgets.QPushButton("Clear")
        self.sine_button = QtWidgets.QPushButton("Generate Sine")
        self.export_button = QtWidgets.QPushButton("Export CSV")
        self.upload_button = QtWidgets.QPushButton("Upload")
        self.close_button = QtWidgets.QPushButton("Quit")

        button_layout.addWidget(self.clear_button)
        button_layout.addWidget(self.sine_button)
        button_layout.addWidget(self.export_button)
        button_layout.addWidget(self.upload_button)
        button_layout.addWidget(self.close_button)
        button_layout.addStretch()

        export_layout = QtWidgets.QHBoxLayout()
        main_layout.addLayout(export_layout)
        export_layout.addWidget(QtWidgets.QLabel("Export Path:"))
        self.export_path_edit = QtWidgets.QLineEdit("waveform.csv")
        export_layout.addWidget(self.export_path_edit, stretch=1)
        self.export_browse_button = QtWidgets.QPushButton("Browse…")
        export_layout.addWidget(self.export_browse_button)

        self.status_label = QtWidgets.QLabel("Ready.")
        main_layout.addWidget(self.status_label)

        self.clear_button.clicked.connect(self.on_clear)
        self.sine_button.clicked.connect(self.on_generate_sine)
        self.export_button.clicked.connect(self.on_export)
        self.upload_button.clicked.connect(self.on_upload)
        self.close_button.clicked.connect(self.close)
        self.export_browse_button.clicked.connect(self.on_browse_export)

        self.freq_input.valueChanged.connect(self._ensure_sample_rate_limit)
        self.sample_rate_input.valueChanged.connect(self._ensure_sample_rate_limit)
        self.canvas.samples_changed.connect(self._update_status_preview)

    def _ensure_sample_rate_limit(self):
        required = self.freq_input.value() * len(self.samples)
        if self.sample_rate_input.value() < required:
            self.sample_rate_input.blockSignals(True)
            self.sample_rate_input.setValue(required)
            self.sample_rate_input.blockSignals(False)
        self._update_status_preview()

    def _update_status_preview(self):
        sample_rate_hz = self.sample_rate_input.value()
        actual_freq = sample_rate_hz / len(self.samples)
        self.status_label.setText(
            f"Samples: {len(self.samples)} | Target freq: {self.freq_input.value():.2f} Hz | "
            f"Playback rate: {sample_rate_hz:.2f} Hz | Actual freq: {actual_freq:.2f} Hz"
        )

    def on_clear(self):
        self.samples.fill(0.0)
        self.canvas.update()
        self.canvas.samples_changed.emit()

    def on_generate_sine(self):
        sample_indices = np.arange(len(self.samples), dtype=np.float64)
        self.samples[:] = np.sin((2.0 * np.pi * (sample_indices + 0.5)) / len(self.samples))
        self.canvas.update()
        self.canvas.samples_changed.emit()

    def on_export(self):
        filename = self.export_path_edit.text().strip()
        if not filename:
            QtWidgets.QMessageBox.warning(self, "Export path missing", "Please specify a file name.")
            return
        try:
            file_path = QtCore.QFileInfo(filename)
            if not file_path.isAbsolute():
                filename = QtCore.QDir.current().absoluteFilePath(filename)

            dac_values = normalize_to_dac(self.samples).astype(np.uint16)
            np.savetxt(filename, dac_values, fmt='%d', newline='\n')
            self.status_label.setText(f"Exported waveform to {filename}")
        except Exception as exc:
            QtWidgets.QMessageBox.critical(self, "Export failed", str(exc))

    def on_browse_export(self):
        current = self.export_path_edit.text().strip() or "waveform.csv"
        filename, _ = QtWidgets.QFileDialog.getSaveFileName(
            self, "Select export path", current, "CSV Files (*.csv);;All Files (*)"
        )
        if filename:
            self.export_path_edit.setText(filename)

    def on_upload(self):
        port = self.port_input.text().strip()
        if not port:
            QtWidgets.QMessageBox.warning(self, "Serial port required", "Please enter a serial port.")
            return

        try:
            dac_values = normalize_to_dac(self.samples)
            freq_hz = self.freq_input.value()
            sample_rate_hz = self.sample_rate_input.value()
            min_rate = freq_hz * len(dac_values)
            if sample_rate_hz < min_rate:
                sample_rate_hz = min_rate
                self.sample_rate_input.setValue(sample_rate_hz)

            # Get selected channel
            channel = 'A' if self.channel_combo.currentIndex() == 0 else 'B'

            sample_rate_word = calculate_sample_rate_word_from_rate(sample_rate_hz)
            packet = build_single_packet(dac_values, sample_rate_word,
                                        loop_mode=self.loop_checkbox.isChecked(),
                                        channel=channel)
            send_packet_via_serial(packet, port)
            self.status_label.setText(
                f"Upload complete: CH-{channel}, freq={freq_hz:.2f} Hz, sample_rate={sample_rate_hz:.2f} Hz on {port}"
            )
        except Exception as exc:
            QtWidgets.QMessageBox.critical(self, "Upload failed", str(exc))


def launch_gui(serial_port: str | None = None) -> int:
    app = QtWidgets.QApplication.instance()
    owns_app = app is None
    if owns_app:
        app = QtWidgets.QApplication(sys.argv)

    window = WaveformEditorWindow(serial_port=serial_port)
    window.show()
    result = app.exec()

    if owns_app:
        return result
    return 0


def main():
    parser = argparse.ArgumentParser(
        description="Custom waveform uploader (supports up to 256 samples per channel)",
        epilog=(
            "Examples:\n"
            "  %(prog)s --gui --port COM3\n"
            "  %(prog)s --file waveform.csv --port COM3 --freq 1000 --loop\n"
            "  %(prog)s --generate sine --samples 256 --port COM3 --freq 2000\n"
            "  %(prog)s --generate sine --samples 128 --port COM3 --freq 1000 --channel B"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument('--gui', action='store_true', help='Launch interactive waveform editor')
    parser.add_argument('--file', type=str, help='Load waveform from CSV/TXT file')
    parser.add_argument('--generate', choices=['sine', 'triangle', 'sawtooth', 'square'],
                        help='Generate predefined waveform')
    parser.add_argument('--samples', type=int, default=256,
                        help='Number of samples when generating waveforms (default: 256, max: 256)')
    parser.add_argument('--freq', type=float, default=DEFAULT_FREQ_HZ,
                        help='Desired waveform frequency in Hz (default: 1000)')
    parser.add_argument('--sample-rate', type=float,
                        help='Playback sample rate in Hz (default: freq * samples)')
    parser.add_argument('--loop', action='store_true', help='Enable loop playback')
    parser.add_argument('--channel', choices=['A', 'B', 'a', 'b'], default='A',
                        help='DAC channel selection (A or B, default: A)')
    parser.add_argument('--port', type=str, help='Serial port (e.g., COM3 or /dev/ttyUSB0)')
    parser.add_argument('--baudrate', type=int, default=115200,
                        help='Serial baudrate (default: 115200)')
    parser.add_argument('--export', type=str, help='Export waveform samples to file')

    args = parser.parse_args()

    if args.gui:
        return launch_gui(serial_port=args.port)

    samples = None

    if args.file:
        samples = load_waveform_from_file(args.file)
        print(f"Loaded {len(samples)} samples from {args.file}")
    elif args.generate:
        idx = np.arange(args.samples, dtype=np.float64)
        phase = (2.0 * np.pi * (idx + 0.5)) / args.samples
        if args.generate == 'sine':
            samples = np.sin(phase)
        elif args.generate == 'triangle':
            samples = 2.0 * np.abs(2.0 * ((idx + 0.5) / args.samples - np.floor((idx + 0.5) / args.samples + 0.5))) - 1.0
        elif args.generate == 'sawtooth':
            samples = 2.0 * ((idx + 0.5) / args.samples - np.floor((idx + 0.5) / args.samples + 0.5))
        elif args.generate == 'square':
            samples = np.sign(np.sin(phase))

        print(f"Generated {args.generate} waveform with {args.samples} samples")

    if samples is not None:
        dac_values = normalize_to_dac(samples)
        required_sample_rate = args.freq * len(dac_values)
        if args.sample_rate:
            sample_rate_hz = max(args.sample_rate, required_sample_rate)
        else:
            sample_rate_hz = required_sample_rate

        sample_rate_word = calculate_sample_rate_word_from_rate(sample_rate_hz)
        actual_output_freq = sample_rate_hz / len(dac_values)

        print(f"Requested frequency: {args.freq} Hz")
        if args.sample_rate and args.sample_rate < required_sample_rate:
            print(f"Adjusted sample rate to {sample_rate_hz:.2f} Hz to satisfy Nyquist.")
        print(f"Playback sample rate: {sample_rate_hz:.2f} Hz")
        print(f"Resulting output frequency: {actual_output_freq:.2f} Hz")
        print(f"Sample rate word: 0x{sample_rate_word:08X}")

        if args.export:
            export_values = normalize_to_dac(samples).astype(np.uint16)
            np.savetxt(args.export, export_values, fmt='%d', newline='\n')
            print(f"Exported 14-bit samples to {args.export}")

        if args.port:
            packet = build_single_packet(dac_values, sample_rate_word,
                                        loop_mode=args.loop,
                                        channel=args.channel.upper())
            send_packet_via_serial(packet, args.port, args.baudrate)

        return 0

    parser.print_help()
    return 1


if __name__ == "__main__":
    exit(main())

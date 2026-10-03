"""Small Windows UI for the CY7C68013A WinUSB ML bridge.

This is the runtime tool. Quartus Programmer is still used only to load the
SOF into the Cyclone II FPGA.
"""
from __future__ import annotations

import ctypes
import queue
import struct
import threading
import tkinter as tk
from tkinter import filedialog, messagebox, ttk
from ctypes import wintypes
from pathlib import Path

from fx2_protocol_test import decode_result, make_four_points, pack_frame

GUID_TEXT = "8f2f6d1e-5c4c-4bc4-a2d2-6b5a6fce7a21"
VID_PID = "VID_0547&PID_1002"

GENERIC_READ, GENERIC_WRITE = 0x80000000, 0x40000000
FILE_SHARE_READ, FILE_SHARE_WRITE = 1, 2
OPEN_EXISTING, FILE_FLAG_OVERLAPPED = 3, 0x40000000
INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value
DIGCF_PRESENT, DIGCF_DEVICEINTERFACE = 2, 0x10


class GUID(ctypes.Structure):
    _fields_ = [("Data1", wintypes.DWORD), ("Data2", wintypes.WORD),
                ("Data3", wintypes.WORD), ("Data4", ctypes.c_ubyte * 8)]


class InterfaceData(ctypes.Structure):
    _fields_ = [("cbSize", wintypes.DWORD), ("InterfaceClassGuid", GUID),
                ("Flags", wintypes.DWORD), ("Reserved", ctypes.c_void_p)]


class PipeInfo(ctypes.Structure):
    _fields_ = [("PipeType", wintypes.ULONG), ("PipeId", ctypes.c_ubyte),
                ("MaximumPacketSize", wintypes.USHORT), ("Interval", ctypes.c_ubyte)]


class InterfaceDescriptor(ctypes.Structure):
    _fields_ = [("bLength", ctypes.c_ubyte), ("bDescriptorType", ctypes.c_ubyte),
                ("bInterfaceNumber", ctypes.c_ubyte), ("bAlternateSetting", ctypes.c_ubyte),
                ("bNumEndpoints", ctypes.c_ubyte), ("bInterfaceClass", ctypes.c_ubyte),
                ("bInterfaceSubClass", ctypes.c_ubyte), ("bInterfaceProtocol", ctypes.c_ubyte),
                ("iInterface", ctypes.c_ubyte)]


class OVERLAPPED(ctypes.Structure):
    _fields_ = [("Internal", ctypes.c_void_p), ("InternalHigh", ctypes.c_void_p),
                ("Offset", wintypes.DWORD), ("OffsetHigh", wintypes.DWORD),
                ("hEvent", ctypes.c_void_p)]


class WINUSB_SETUP_PACKET(ctypes.Structure):
    _fields_ = [("RequestType", ctypes.c_ubyte), ("Request", ctypes.c_ubyte),
                ("Value", wintypes.USHORT), ("Index", wintypes.USHORT),
                ("Length", wintypes.USHORT)]


def make_guid(text: str) -> GUID:
    import uuid
    u = uuid.UUID(text)
    g = GUID(u.time_low, u.time_mid, u.time_hi_version, (ctypes.c_ubyte * 8).from_buffer_copy(u.bytes[8:]))
    return g


class FX2:
    def __init__(self) -> None:
        self.dev = self.usb = None
        self.out_pipe = self.in_pipe = None
        self.last_result_cycles = None
        self.path = ""
        self.setup = ctypes.WinDLL("setupapi.dll")
        self.k32 = ctypes.WinDLL("kernel32.dll")
        self.wusb = ctypes.WinDLL("winusb.dll")
        # ctypes otherwise assumes 32-bit integer return values.  These APIs
        # pass 64-bit handles/pointers on a 64-bit Windows installation.
        self.setup.SetupDiGetClassDevsW.restype = ctypes.c_void_p
        self.setup.SetupDiEnumDeviceInterfaces.argtypes = [ctypes.c_void_p, ctypes.c_void_p,
            ctypes.POINTER(GUID), wintypes.DWORD, ctypes.POINTER(InterfaceData)]
        self.setup.SetupDiEnumDeviceInterfaces.restype = wintypes.BOOL
        self.setup.SetupDiGetDeviceInterfaceDetailW.argtypes = [ctypes.c_void_p,
            ctypes.POINTER(InterfaceData), ctypes.c_void_p, wintypes.DWORD,
            ctypes.POINTER(wintypes.DWORD), ctypes.c_void_p]
        self.setup.SetupDiGetDeviceInterfaceDetailW.restype = wintypes.BOOL
        self.setup.SetupDiDestroyDeviceInfoList.argtypes = [ctypes.c_void_p]
        self.setup.SetupDiDestroyDeviceInfoList.restype = wintypes.BOOL
        self.k32.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
            ctypes.c_void_p, wintypes.DWORD, wintypes.DWORD, ctypes.c_void_p]
        self.k32.CreateFileW.restype = ctypes.c_void_p
        self.k32.CloseHandle.argtypes = [ctypes.c_void_p]
        self.k32.CreateEventW.argtypes = [ctypes.c_void_p, wintypes.BOOL, wintypes.BOOL, wintypes.LPCWSTR]
        self.k32.CreateEventW.restype = ctypes.c_void_p
        self.k32.WaitForSingleObject.argtypes = [ctypes.c_void_p, wintypes.DWORD]
        self.k32.WaitForSingleObject.restype = wintypes.DWORD
        self.k32.GetOverlappedResult.argtypes = [ctypes.c_void_p, ctypes.POINTER(OVERLAPPED), ctypes.POINTER(wintypes.DWORD), wintypes.BOOL]
        self.k32.GetOverlappedResult.restype = wintypes.BOOL
        self.k32.CancelIoEx.argtypes = [ctypes.c_void_p, ctypes.POINTER(OVERLAPPED)]
        self.k32.CancelIoEx.restype = wintypes.BOOL
        self.wusb.WinUsb_Initialize.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)]
        self.wusb.WinUsb_Initialize.restype = wintypes.BOOL
        self.wusb.WinUsb_Free.argtypes = [ctypes.c_void_p]
        self.wusb.WinUsb_Free.restype = wintypes.BOOL
        self.wusb.WinUsb_QueryInterfaceSettings.argtypes = [ctypes.c_void_p, ctypes.c_ubyte,
            ctypes.POINTER(InterfaceDescriptor)]
        self.wusb.WinUsb_QueryInterfaceSettings.restype = wintypes.BOOL
        self.wusb.WinUsb_QueryPipe.argtypes = [ctypes.c_void_p, ctypes.c_ubyte, ctypes.c_ubyte,
            ctypes.POINTER(PipeInfo)]
        self.wusb.WinUsb_QueryPipe.restype = wintypes.BOOL
        self.wusb.WinUsb_SetPipePolicy.argtypes = [ctypes.c_void_p, ctypes.c_ubyte,
            ctypes.c_ubyte, wintypes.ULONG, ctypes.c_void_p]
        self.wusb.WinUsb_SetPipePolicy.restype = wintypes.BOOL
        self.wusb.WinUsb_ResetPipe.argtypes = [ctypes.c_void_p, ctypes.c_ubyte]
        self.wusb.WinUsb_ResetPipe.restype = wintypes.BOOL
        self.wusb.WinUsb_ControlTransfer.argtypes = [ctypes.c_void_p, WINUSB_SETUP_PACKET,
            ctypes.c_void_p, wintypes.ULONG, ctypes.POINTER(wintypes.ULONG), ctypes.c_void_p]
        self.wusb.WinUsb_ControlTransfer.restype = wintypes.BOOL
        self.wusb.WinUsb_WritePipe.argtypes = [ctypes.c_void_p, ctypes.c_ubyte, ctypes.c_void_p,
                                               wintypes.ULONG, ctypes.POINTER(wintypes.ULONG), ctypes.POINTER(OVERLAPPED)]
        self.wusb.WinUsb_WritePipe.restype = wintypes.BOOL
        self.wusb.WinUsb_ReadPipe.argtypes = [ctypes.c_void_p, ctypes.c_ubyte, ctypes.c_void_p,
                                              wintypes.ULONG, ctypes.POINTER(wintypes.ULONG), ctypes.POINTER(OVERLAPPED)]
        self.wusb.WinUsb_ReadPipe.restype = wintypes.BOOL
        self.wusb.WinUsb_GetOverlappedResult.argtypes = [ctypes.c_void_p, ctypes.POINTER(OVERLAPPED),
                                                         ctypes.POINTER(wintypes.ULONG), wintypes.BOOL]
        self.wusb.WinUsb_GetOverlappedResult.restype = wintypes.BOOL

    def _find_path(self) -> str:
        guid = make_guid(GUID_TEXT)
        h = self.setup.SetupDiGetClassDevsW(ctypes.byref(guid), None, None,
                                            DIGCF_PRESENT | DIGCF_DEVICEINTERFACE)
        if h == INVALID_HANDLE_VALUE:
            raise OSError("SetupDiGetClassDevsW failed")
        try:
            i = 0
            while True:
                data = InterfaceData()
                data.cbSize = ctypes.sizeof(InterfaceData)
                required = wintypes.DWORD()
                ok = self.setup.SetupDiEnumDeviceInterfaces(h, None, ctypes.byref(guid), i,
                                                             ctypes.byref(data))
                if not ok:
                    break
                self.setup.SetupDiGetDeviceInterfaceDetailW(h, ctypes.byref(data), None, 0,
                                                            ctypes.byref(required), None)
                buf = ctypes.create_string_buffer(required.value)
                ctypes.cast(buf, ctypes.POINTER(wintypes.DWORD))[0] = 8 if ctypes.sizeof(ctypes.c_void_p) == 8 else 6
                if self.setup.SetupDiGetDeviceInterfaceDetailW(h, ctypes.byref(data), buf,
                                                                required.value, ctypes.byref(required), None):
                    path = ctypes.wstring_at(ctypes.addressof(buf) + 8)
                    # Some ctypes/SetupAPI combinations omit the first slash
                    # from the returned device path.  WinUSB requires the
                    # canonical \\\\?\\ prefix for CreateFileW.
                    if path.startswith("?\\"):
                        path = "\\\\" + path
                    if VID_PID.lower() in path.lower():
                        return path
                i += 1
        finally:
            self.setup.SetupDiDestroyDeviceInfoList(h)
        raise FileNotFoundError("CY7C68013A WinUSB interface not found")

    def open(self) -> str:
        self.path = self._find_path()
        h = self.k32.CreateFileW(self.path, GENERIC_READ | GENERIC_WRITE,
                                 FILE_SHARE_READ | FILE_SHARE_WRITE, None,
                                 OPEN_EXISTING, FILE_FLAG_OVERLAPPED, None)
        if h == INVALID_HANDLE_VALUE:
            code = self.k32.GetLastError()
            raise OSError(f"CreateFileW failed (Windows error {code})")
        self.dev = h
        usb = ctypes.c_void_p()
        if not self.wusb.WinUsb_Initialize(h, ctypes.byref(usb)):
            code = self.k32.GetLastError()
            raise OSError(f"WinUsb_Initialize failed (Windows error {code})")
        self.usb = usb
        desc = InterfaceDescriptor()
        if not self.wusb.WinUsb_QueryInterfaceSettings(usb, 0, ctypes.byref(desc)):
            raise OSError("WinUsb_QueryInterfaceSettings failed")
        pipes = []
        for n in range(desc.bNumEndpoints):
            p = PipeInfo()
            if self.wusb.WinUsb_QueryPipe(usb, 0, n, ctypes.byref(p)):
                pipes.append(p)
        outs = [p.PipeId for p in pipes if p.PipeId & 0x80 == 0]
        ins = [p.PipeId for p in pipes if p.PipeId & 0x80]
        if not outs or not ins:
            raise OSError(f"missing bulk endpoints: {[hex(x) for x in outs]} / {[hex(x) for x in ins]}")
        self.out_pipe, self.in_pipe = outs[0], ins[0]
        # Clear endpoint toggles/stalls left by a previous FX2 RAM image.
        self.wusb.WinUsb_ResetPipe(self.usb, self.out_pipe)
        self.wusb.WinUsb_ResetPipe(self.usb, self.in_pipe)
        # SET_INTERFACE is handled by the FX2 firmware and reruns fifo_setup,
        # flushing stale EP2/EP6 bytes left by a previous FPGA configuration.
        setup = WINUSB_SETUP_PACKET(0x01, 0x0B, 0, 0, 0)
        transferred = wintypes.ULONG()
        if not self.wusb.WinUsb_ControlTransfer(self.usb, setup, None, 0,
                                                ctypes.byref(transferred), None):
            raise OSError("WinUsb SET_INTERFACE failed")
        # Some FX2 RAM images need the FIFO setup request twice after a
        # re-enumeration: the first request changes the interface state and
        # the second clears the newly-created EP6 buffer.
        if not self.wusb.WinUsb_ControlTransfer(self.usb, setup, None, 0,
                                                ctypes.byref(transferred), None):
            raise OSError("WinUsb second SET_INTERFACE failed")
        # SET_INTERFACE reruns fifo_setup in the FX2 firmware and flushes the
        # endpoint.  Do not issue a speculative bulk read here: on some
        # WinUSB versions it leaves an overlapped read pending and steals the
        # first response of the next transaction.
        # PIPE_TRANSFER_TIMEOUT = 0x03; keep a failed FPGA response from
        # blocking the UI forever.
        timeout_ms = wintypes.ULONG(3000)
        self.wusb.WinUsb_SetPipePolicy(self.usb, self.in_pipe, 0x03,
                                       ctypes.sizeof(timeout_ms), ctypes.byref(timeout_ms))
        self._drain_stale_in()
        return f"connected; OUT 0x{self.out_pipe:02X}, IN 0x{self.in_pipe:02X}"

    def close(self) -> None:
        if self.usb:
            self.wusb.WinUsb_Free(self.usb)
        if self.dev and self.dev != INVALID_HANDLE_VALUE:
            self.k32.CloseHandle(self.dev)
        self.usb = self.dev = None

    def _drain_stale_in(self) -> None:
        """Discard residual EP6 bytes left by an FPGA reconfiguration."""
        short_timeout = wintypes.ULONG(100)
        self.wusb.WinUsb_SetPipePolicy(self.usb, self.in_pipe, 0x03,
                                       ctypes.sizeof(short_timeout), ctypes.byref(short_timeout))
        try:
            for _ in range(64):
                # The bridge emits a 24-byte packet (two six-word result
                # frames).  Drain a whole packet; a 2-byte read can leave the
                # remaining stale frame queued on WinUSB.
                buf = ctypes.create_string_buffer(24)
                got = wintypes.ULONG()
                event = self.k32.CreateEventW(None, True, False, None)
                if not event:
                    break
                ov = OVERLAPPED(); ov.hEvent = event
                try:
                    ok = self.wusb.WinUsb_ReadPipe(self.usb, self.in_pipe, buf, 24,
                                                   ctypes.byref(got), ctypes.byref(ov))
                    if not ok:
                        code = self.k32.GetLastError()
                        if code != 997:
                            break
                        if self.k32.WaitForSingleObject(event, 100) != 0:
                            self.k32.CancelIoEx(self.dev, ctypes.byref(ov))
                            break
                        if not self.wusb.WinUsb_GetOverlappedResult(
                                self.usb, ctypes.byref(ov), ctypes.byref(got), False):
                            break
                    if got.value == 0:
                        break
                finally:
                    self.k32.CloseHandle(event)
        finally:
            timeout_ms = wintypes.ULONG(3000)
            self.wusb.WinUsb_SetPipePolicy(self.usb, self.in_pipe, 0x03,
                                           ctypes.sizeof(timeout_ms), ctypes.byref(timeout_ms))

    def _read_exact(self, size: int) -> bytes:
        buf = ctypes.create_string_buffer(size)
        got = wintypes.ULONG()
        event = self.k32.CreateEventW(None, True, False, None)
        if not event:
            raise OSError("CreateEventW failed")
        ov = OVERLAPPED(); ov.hEvent = event
        try:
            ok = self.wusb.WinUsb_ReadPipe(self.usb, self.in_pipe, buf, size,
                                           ctypes.byref(got), ctypes.byref(ov))
            if not ok:
                code = self.k32.GetLastError()
                if code != 997:
                    raise OSError(f"WinUsb_ReadPipe failed (Windows error {code})")
                if self.k32.WaitForSingleObject(event, 3000) != 0:
                    self.k32.CancelIoEx(self.dev, ctypes.byref(ov))
                    raise TimeoutError("WinUsb_ReadPipe timed out after 3 seconds")
                if not self.wusb.WinUsb_GetOverlappedResult(self.usb, ctypes.byref(ov),
                                                           ctypes.byref(got), False):
                    raise OSError("WinUsb_GetOverlappedResult failed")
            if got.value != size:
                raise OSError(f"short result: {got.value} bytes")
            return bytes(buf.raw)
        finally:
            self.k32.CloseHandle(event)

    def _read_result_chunks(self) -> list[int]:
        """Read both redundant six-word frames as one 24-byte EP6 packet."""
        return list(struct.unpack("<12H", self._read_exact(24)))

    def _decode_packet(self, words: list[int]) -> dict[str, int | bool] | None:
        """Decode one rotated packet, rejecting implausible transport mixes."""
        marker_index = next((i for i, value in enumerate(words)
                             if value == 0xC33C), None)
        if marker_index is None:
            return None
        frame = words[marker_index:] + words[:marker_index]
        if (frame[1] & 0xF) > 9:
            return None
        result = decode_result(frame)
        # The current core completes in well under one million cycles.  A
        # much larger value indicates that words from two FX2 packets were
        # mixed, even if the marker itself survived.
        if result["cycles"] > 0x01000000:
            return None
        return result

    def _decode_stream(self, words: list[int]) -> dict[str, int | bool] | None:
        """Find the complete result frame in the response stream."""
        newest = None
        for start in range(max(0, len(words) - 5)):
            if words[start] == 0xC33C:
                result = self._decode_packet(words[start:start + 6])
                if result is not None:
                    newest = result
        if newest is not None:
            return newest
        # A single complete packet may be rotated, for example after a
        # reconnect.  Preserve the fallback for diagnostic/raw use.
        if len(words) == 6:
            return self._decode_packet(words)
        return None

    def transact(self, words: list[int], raw: bool = False, read_words: int = 6) -> dict | list[int]:
        payload = struct.pack("<%dH" % len(words), *words)
        sent = wintypes.ULONG()
        write_event = self.k32.CreateEventW(None, True, False, None)
        if not write_event:
            raise OSError("CreateEventW failed for write")
        write_ov = OVERLAPPED(); write_ov.hEvent = write_event
        try:
            ok = self.wusb.WinUsb_WritePipe(self.usb, self.out_pipe, payload, len(payload),
                                            ctypes.byref(sent), ctypes.byref(write_ov))
            if not ok:
                code = self.k32.GetLastError()
                if code != 997:
                    raise OSError(f"WinUsb_WritePipe failed (Windows error {code})")
                if self.k32.WaitForSingleObject(write_event, 3000) != 0:
                    self.k32.CancelIoEx(self.dev, ctypes.byref(write_ov))
                    raise TimeoutError("WinUsb_WritePipe timed out after 3 seconds")
                if not self.wusb.WinUsb_GetOverlappedResult(self.usb, ctypes.byref(write_ov),
                                                           ctypes.byref(sent), False):
                    raise OSError("WinUsb_GetOverlappedResult failed for write")
        finally:
            self.k32.CloseHandle(write_event)
        if sent.value != len(payload):
            raise OSError(f"short USB write: {sent.value} of {len(payload)} bytes")
        if not raw and read_words == 6:
            # The FPGA cycle counter increases for every accepted frame.  A
            # reconnect can expose an old duplicate response before the
            # current response, so reject non-newer packets and continue
            # reading until the current transaction is observed.
            for _ in range(4):
                result = self._decode_stream(self._read_result_chunks())
                if result is None:
                    raise OSError("no complete FPGA result frame received")
                stale_before_run = self.last_result_cycles is None and result["cycles"] > 1_000_000
                stale_duplicate = (self.last_result_cycles is not None and
                                   result["cycles"] <= self.last_result_cycles)
                if not stale_before_run and not stale_duplicate:
                    self.last_result_cycles = result["cycles"]
                    return result
            raise OSError("FPGA result did not advance after four response packets")
            return best[0]
        else:
            words = list(struct.unpack("<%dH" % read_words, self._read_exact(2 * read_words)))
        if raw:
            return words
        # WinUSB/FX2 may present the complete six-word packet rotated at a
        # bulk-packet boundary.  Rotate at the unique marker instead of
        # assuming that the marker is word zero.
        result = self._decode_packet(words)
        if result is None:
            raise OSError("invalid FPGA result words: " + " ".join(f"0x{x:04X}" for x in words))
        return result


class App:
    def __init__(self, root: tk.Tk) -> None:
        self.root, self.dev, self.pixels = root, FX2(), make_four_points()
        self.events = queue.Queue()
        root.title("Cyclone II FX2 ML tester")
        root.geometry("720x560")
        top = ttk.Frame(root, padding=8); top.pack(fill="x")
        self.status = tk.StringVar(value="not connected")
        ttk.Label(top, textvariable=self.status).pack(side="left")
        ttk.Button(top, text="Refresh / connect", command=self.connect).pack(side="right")
        controls = ttk.Frame(root, padding=8); controls.pack(fill="x")
        ttk.Button(controls, text="Four points test", command=lambda: self.start(make_four_points())).pack(side="left")
        ttk.Button(controls, text="Choose photo", command=self.photo).pack(side="left", padx=6)
        ttk.Button(controls, text="Send frame", command=lambda: self.start(self.pixels)).pack(side="left")
        self.result = tk.StringVar(value="result: —")
        ttk.Label(root, textvariable=self.result, font=("Segoe UI", 14)).pack(anchor="w", padx=8)
        self.canvas = tk.Canvas(root, width=280, height=280, background="white"); self.canvas.pack(pady=8)
        self.log = tk.Text(root, height=10, state="disabled"); self.log.pack(fill="both", expand=True, padx=8, pady=8)
        self.draw(); root.after(100, self.poll)

    def write(self, s: str) -> None:
        self.log.configure(state="normal"); self.log.insert("end", s + "\n"); self.log.see("end"); self.log.configure(state="disabled")

    def draw(self) -> None:
        self.canvas.delete("all")
        for r in range(14):
            for c in range(14):
                v = self.pixels[r * 14 + c]
                color = "#%02x%02x%02x" % (255 - v * 17, 255 - v * 17, 255 - v * 17)
                self.canvas.create_rectangle(c * 20, r * 20, c * 20 + 20, r * 20 + 20, fill=color, outline="#dddddd")

    def connect(self) -> None:
        try:
            self.dev.close(); msg = self.dev.open(); self.status.set(msg); self.write(msg)
        except Exception as e:
            self.status.set("not connected"); self.write("connect error: " + str(e))

    def photo(self) -> None:
        path = filedialog.askopenfilename(filetypes=[("Images", "*.png *.jpg *.jpeg *.bmp")])
        if not path: return
        try:
            from train import normalize_photo
            self.pixels = normalize_photo(Path(path)).tolist(); self.draw(); self.write("loaded " + path)
        except Exception as e:
            messagebox.showerror("Photo", str(e))

    def start(self, pixels: list[int]) -> None:
        self.pixels = pixels; self.draw(); threading.Thread(target=self.worker, daemon=True).start()

    def worker(self) -> None:
        try:
            self.events.put("sending")
            if not self.dev.usb: self.dev.open()
            self.events.put("waiting for FPGA result")
            result = self.dev.transact(pack_frame(self.pixels)); self.events.put(result)
        except Exception as e:
            # A failed synchronous WinUSB read can leave the pipe unusable.
            # Release it so the next click can reconnect automatically.
            self.dev.close()
            self.events.put(e)

    def poll(self) -> None:
        try:
            while True:
                item = self.events.get_nowait()
                if item == "sending": self.status.set("sending frame..."); self.write("sending 99 words")
                elif item == "waiting for FPGA result": self.status.set("waiting for FPGA result..."); self.write("waiting for 6 result words")
                elif isinstance(item, Exception): self.status.set("transfer failed; ready to retry"); self.write("transfer error: " + str(item))
                else:
                    self.status.set("result received")
                    text = f"digit={item['digit']} accepted={item['accepted']} confidence={item['confidence']} margin={item['margin']} cycles={item['cycles']}"
                    self.result.set("result: " + text); self.write(text)
        except queue.Empty: pass
        self.root.after(100, self.poll)


if __name__ == "__main__":
    root = tk.Tk(); App(root); root.mainloop()

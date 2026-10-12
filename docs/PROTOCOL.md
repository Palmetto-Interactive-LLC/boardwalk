# Treadmill protocol notes

Boardwalk speaks the Bluetooth SIG **Fitness Machine Service (FTMS)**. This page covers the parts Boardwalk uses and the firmware behavior we measured on real hardware. It should save you an afternoon if you're writing your own controller.

All measurements below come from a **YIJIAN ZBJ_38A_BT** treadmill controller on 2026-10-12.

## The tested device

The controller advertises as `ESLinker-xxxxxx` with service `0x1826` in its advertisement. Its Device Information service reports:

| Field | Value |
| --- | --- |
| Manufacturer | `YIJIAN` |
| Model | `ZBJ_38A_BT` |
| Hardware revision | `HZ-MBT0310` |
| Firmware revision | `09.19.01` |
| Software revision | `V1.0.0` |

Besides FTMS it exposes two vendor services (`0xFFF0` and `02f00000-…-fe00`). Boardwalk doesn't need either.

## Characteristics Boardwalk uses

All of these live under the Fitness Machine service, `0x1826`.

| UUID | Name | Properties | Use |
| --- | --- | --- | --- |
| `0x2ACD` | Treadmill Data | notify | Live belt speed, about once a second |
| `0x2AD3` | Training Status | notify, read | Tells us when the start-up countdown ends |
| `0x2AD4` | Supported Speed Range | read | Min, max and step speed |
| `0x2AD9` | Fitness Machine Control Point | write, indicate | Start, stop, set speed |

On the tested unit, Supported Speed Range reads `50 00 80 02 0a 00`. That's 0.80 to 6.40 km/h with a 0.10 km/h step, as three little-endian `uint16` values in units of 0.01 km/h.

## Commands

Write these to the Control Point (`0x2AD9`) with response.

| Action | Bytes | Notes |
| --- | --- | --- |
| Request Control | `00` | Send before Start. |
| Start / Resume | `07` | |
| Stop | `08 01` | `08 02` would be Pause. |
| Set Target Speed | `02 LL HH` | `uint16`, little-endian, units of 0.01 km/h. 2.24 km/h is `02 e0 00`. |

Boardwalk's On button sends `00`, waits 0.3 s, then sends `07`.

## Reading speed

Treadmill Data (`0x2ACD`) starts with a 16-bit flags field. When bit 0 ("More Data") is **clear**, the next two bytes are the instantaneous speed as a `uint16` in units of 0.01 km/h.

```
86 04 50 00 50 00 00 00 00 00 00 00 00 00 03 00
└flags┘ └speed┘
        0x0050 = 80 → 0.80 km/h
```

## Firmware quirks

These are the behaviors that weren't obvious from the spec. Each one caused a real bug before we accounted for it.

### 1. The control point never answers

The FTMS spec says each control point write gets an indication back (`80 <opcode> <result>`). This firmware never sends one, even with indications enabled. Commands still work. So don't wait for the response, or every command will look like it timed out. Boardwalk confirms commands by watching the speed in Treadmill Data instead.

Enable indications on the control point anyway. The spec expects it, and other FTMS firmware may depend on it.

### 2. Speed changes are ignored during the start-up countdown

After Start, the treadmill beeps and runs at its minimum speed for about two seconds. Training Status goes like this:

| Time after Start | Training Status | Belt |
| --- | --- | --- |
| ~0.1 s | `0x0E` Pre-Workout | Starts at 0.80 km/h |
| ~2 s | `0x0D` Manual Mode | Now accepts speed changes |

Any Set Target Speed written while the status is `0x0E` is **silently dropped**. Here's a measured sequence:

| Command | Sent at | Result |
| --- | --- | --- |
| Start | 0 s | Belt 0.80 km/h |
| Set 1.5 km/h | ~0.6 s (during countdown) | Ignored, belt stays 0.80 |
| Set 1.0 km/h | ~5.6 s (after countdown) | Belt 0.96 km/h within a second (see quirk 3) |

Boardwalk queues the target and sends it when Training Status reports `0x0D`. As a fallback, it also sends it 3.5 s after the belt starts moving, for treadmills that don't send Training Status.

### 3. It works in 0.1 mph steps, with 1 mph = 1.6 km/h

The treadmill takes km/h on the wire, but internally it moves in 0.1 mph steps and converts with 1.6 rather than the true 1.609. Any target is **floored** to a multiple of 0.16 km/h:

| Sent | Belt reports | Equals |
| --- | --- | --- |
| 1.10 km/h | 0.96 km/h | 0.6 mph |
| 1.40 km/h | 1.28 km/h | 0.8 mph |
| 2.40 km/h | 2.40 km/h | 1.5 mph |
| 1.12 km/h | 1.12 km/h | 0.7 mph |

So to land on an exact mph value, send `mph × 10 × 16` in units of 0.01 km/h. Boardwalk does that. The speed range is really 0.5 to 4.0 mph.

On a treadmill that works natively in km/h, this costs at most about 0.6% accuracy. Nobody walking will notice.

### 4. Start always begins at minimum speed

In every test, Start ignored any earlier target and began at 0.80 km/h (0.5 mph). Boardwalk applies its start speed (1.4 mph by default) once the countdown ends.

### 5. One connection at a time

The treadmill accepts a single Bluetooth connection. If its phone app is connected, Boardwalk won't find it until that app lets go.

## Reproducing these measurements

The quickest way to poke at a treadmill is Python with [`bleak`](https://github.com/hbldh/bleak). This sketch connects, logs every notification, and sends Start then Stop:

```python
import asyncio
from bleak import BleakClient, BleakScanner

CP = "00002ad9-0000-1000-8000-00805f9b34fb"

async def main():
    dev = await BleakScanner.find_device_by_filter(
        lambda d, adv: "00001826-0000-1000-8000-00805f9b34fb" in adv.service_uuids)
    async with BleakClient(dev) as c:
        for s in c.services:
            for ch in s.characteristics:
                if {"notify", "indicate"} & set(ch.properties):
                    await c.start_notify(ch, lambda h, d, u=ch.uuid[4:8]: print(u, bytes(d).hex()))
        await c.write_gatt_char(CP, b"\x00", response=True)
        await c.write_gatt_char(CP, b"\x07", response=True)   # belt starts
        await asyncio.sleep(8)
        await c.write_gatt_char(CP, b"\x08\x01", response=True)
        await asyncio.sleep(3)

asyncio.run(main())
```

Clear the belt before running it.

## References

- Bluetooth SIG, [Fitness Machine Service 1.0](https://www.bluetooth.com/specifications/specs/fitness-machine-service-1-0/)
- Bluetooth SIG, [Assigned Numbers](https://www.bluetooth.com/specifications/assigned-numbers/), for the `0x2Axx` characteristic UUIDs

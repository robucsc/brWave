import aifc
import struct
import os

print("Parsing WaveTables.swift...")
with open("brWave/WaveTables.swift", "r") as f:
    content = f.read()

start_idx = content.find("static let tables: [[[Int8]]] = [")
if start_idx == -1:
    print("Could not find table def")
    exit(1)
start_idx = content.find("[", start_idx + len("static let tables: [[[Int8]]] = "))

tables = []
lines = content[start_idx:].splitlines()
current_table = []

for line in lines:
    line = line.split("//")[0].strip()
    if not line:
        continue
    if line.startswith("[") and line.endswith("],"):
        nums_str = line.strip("[], ")
        if not nums_str:
            continue
        try:
            nums = [int(x) for x in nums_str.split(",")]
        except ValueError:
            continue
            
        # The Swift file has 128 samples per slot, but only the first 64 are the correct hal-cycle.
        half_wave = nums[:64]
        current_table.append(half_wave)
        
        if len(current_table) == 64:
            tables.append(current_table)
            current_table = []

print(f"Parsed {len(tables)} wavetables.")

os.makedirs("PPG_AIFFs", exist_ok=True)

for i, table in enumerate(tables):
    filename = f"PPG_AIFFs/Wavetable_{i+1:02d}.aiff"
    with aifc.open(filename, 'wb') as aiff:
        aiff.setnchannels(1)
        aiff.setsampwidth(2) # 16 bit
        aiff.setframerate(44100) # standard sample rate
        
        for wave_idx, half_wave in enumerate(table):
            # Authentic PPG hardware generates the second half of the cycle by 
            # playing the 64 stored samples **back-to-front** while inverting their amplitude.
            # This 'reversed-inverted' mirror is what ensures phase continuities (no straight vertical jumps).
            full_wave = half_wave + [-x for x in reversed(half_wave)]
            
            frames = []
            for sample in full_wave:
                s = sample * 256
                if s > 32767: s = 32767
                if s < -32768: s = -32768
                frames.append(struct.pack('>h', s))
            
            aiff.writeframes(b''.join(frames))

print("Done making fixed AIFFs (128 samples per cycle).")

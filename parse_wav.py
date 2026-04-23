import struct
import sys

def parse_wav(filename):
    with open(filename, "rb") as f:
        data = f.read()
    
    if data[0:4] != b"RIFF":
        print("Not RIFF")
        return
    if data[8:12] != b"WAVE":
        print("Not WAVE")
        return
        
    pos = 12
    while pos < len(data):
        chunk_id = data[pos:pos+4]
        if len(chunk_id) < 4:
            break
        chunk_size = struct.unpack("<I", data[pos+4:pos+8])[0]
        # remove the f-string issue:
        id_str = chunk_id.decode(errors="ignore")
        print("Chunk: " + id_str + " Size: " + str(chunk_size))
        
        if chunk_id == b"smpl":
            smpl_data = data[pos+8:pos+8+chunk_size]
            manuf, prod, period, root, fract, smpte, smpte_off, num_loops, sampler_data = struct.unpack("<IIIIIIIII", smpl_data[0:36])
            print("  smpl metadata: RootKey=" + str(root) + " NumLoops=" + str(num_loops))
            if num_loops > 0:
                loop_data = smpl_data[36:36+24]
                cue, type_, start, end, fract, play_count = struct.unpack("<IIIIII", loop_data)
                print("  Loop 0: Start=" + str(start) + " End=" + str(end))
                
        pos += 8 + chunk_size
        if chunk_size % 2 != 0:
            pos += 1

parse_wav("docs/PPG_Wave_3.V_Presets/PPG 3V - Sounds by Designers/Wolfgang Palm Soundset/Samples/t3_T1020_Bell.wav")

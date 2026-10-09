from macho import architectures, ARM64
import struct

def thin(subtype):
    return struct.pack('<8I',0xfeedfacf,ARM64,subtype,6,0,0,0,0)
def fat(first=0,second=2):
    header=struct.pack('>2I',0xcafebabe,2)+struct.pack('>5I',ARM64,first,48,32,0)+struct.pack('>5I',ARM64,second,80,32,0)
    return header+thin(first)+thin(second)
assert architectures(fat()) == {(ARM64,0),(ARM64,2)}
assert architectures(thin(0x80000002)) == {(ARM64,2)}
for invalid in [b'', b'not-macho', fat()[:-1], fat(0,0), struct.pack('<8I',0xfeedfacf,ARM64,2,6,1,0,0,0)]:
    try: architectures(invalid)
    except ValueError: pass
    else: raise AssertionError('Malformed binary accepted')
print('PASS: actual Mach-O slices, arm64e capability bits and malformed payload rejection')

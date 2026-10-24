"""Parse CPU identities of thin/fat Mach-O without relying on file/lipo text."""
import struct
ARM64 = 0x0100000c

def architectures(data):
    if len(data) < 8:
        raise ValueError('Truncated Mach-O')
    magic = data[:4]
    if magic in (b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca'):
        endian = '>' if magic[0] == 0xca else '<'
        fat64 = magic in (b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca')
        count = struct.unpack_from(endian+'I',data,4)[0]
        if count == 0 or count > 64: raise ValueError('Invalid fat slice count')
        stride = 32 if fat64 else 20
        if len(data) < 8+count*stride: raise ValueError('Truncated fat header')
        result = set()
        for index in range(count):
            pos = 8+index*stride
            cpu, subtype = struct.unpack_from(endian+'II',data,pos)
            offset, size = struct.unpack_from(endian+('QQ' if fat64 else 'II'),data,pos+8)
            if offset < 8+count*stride or size < 32 or offset+size > len(data): raise ValueError('Invalid Mach-O slice extent')
            identities = architectures(data[offset:offset+size])
            expected = (cpu, subtype & 0x00ffffff)
            if identities != {expected}: raise ValueError('Fat header does not match its Mach-O slice')
            if expected in result: raise ValueError('Duplicate Mach-O slice')
            result.update(identities)
        return result
    if magic not in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf'): raise ValueError('Not a 64-bit Mach-O')
    if len(data) < 32: raise ValueError('Truncated thin header')
    endian = '<' if magic[0] == 0xcf else '>'
    cpu, subtype, filetype, commands, commandbytes = struct.unpack_from(endian+'IIIII',data,4)
    if filetype not in (2,6,8): raise ValueError('Not an executable/dylib/bundle')
    if 32+commandbytes > len(data): raise ValueError('Truncated load commands')
    pos = 32
    for _ in range(commands):
        if pos+8 > 32+commandbytes: raise ValueError('Truncated load command')
        _, size = struct.unpack_from(endian+'II',data,pos)
        if size < 8 or pos+size > 32+commandbytes: raise ValueError('Invalid load command')
        pos += size
    if pos != 32+commandbytes: raise ValueError('Incorrect command byte count')
    return {(cpu,subtype & 0x00ffffff)}

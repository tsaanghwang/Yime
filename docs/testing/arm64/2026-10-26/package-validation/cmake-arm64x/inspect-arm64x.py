from pathlib import Path
import struct, json, hashlib

root = Path('.tmp/yimecore-platform-experiments/arm64x-20261026-194641-6bb6f5c1')
path = root / 'ec/Release/YimeTextServiceExperiment.dll'
data = path.read_bytes()
u16 = lambda o: struct.unpack_from('<H', data, o)[0]
u32 = lambda o: struct.unpack_from('<I', data, o)[0]
u64 = lambda o: struct.unpack_from('<Q', data, o)[0]
pe = u32(0x3c)
opt = pe + 24
sec = opt + u16(pe + 20)
sections=[]
for i in range(u16(pe+6)):
    at=sec+i*40
    sections.append(dict(index=i+1,name=data[at:at+8].split(b'\0')[0].decode(),virtual_size=u32(at+8),rva=u32(at+12),raw_size=u32(at+16),raw_offset=u32(at+20)))
def raw(rva, size=1):
    for item in sections:
        delta=rva-item['rva']
        if 0 <= delta and delta+size <= item['raw_size']:
            offset=item['raw_offset']+delta
            assert offset+size <= len(data)
            return offset
    raise ValueError(f'unmapped rva {rva:x}, size {size}')
base=u64(opt+24)
config_rva=u32(opt+112+10*8)
config_directory_size=u32(opt+112+10*8+4)
config=raw(config_rva, config_directory_size)
chpe=u64(config+200)
section_index=u16(config+228)
delta=u32(config+224)
table=sections[section_index-1]['raw_offset']+delta
version=u32(table)
size=u32(table+4)
assert version==1
cursor=table+8
end=cursor+size
entries=[]
while cursor<end:
    symbol=u64(cursor); reloc_size=u32(cursor+8)
    assert cursor+12+reloc_size<=end
    entries.append(dict(header_offset=cursor,header_size=12,symbol=symbol,base_reloc_size=reloc_size,payload_offset=cursor+12))
    cursor+=12+reloc_size
assert cursor==end
result=dict(path=str(path.resolve()),bytes=len(data),sha256=hashlib.sha256(data).hexdigest(),machine=f'0x{u16(pe+4):04x}',optional_header_magic=f'0x{u16(opt):x}',image_base=base,load_config=dict(rva=config_rva,file_offset=config,declared_size=u32(config),directory_size=config_directory_size,DynamicValueRelocTable=u64(config+192),CHPEMetadataPointer=chpe,CHPEMetadataFileOffset=raw(chpe-base,4),CHPEMetadataVersion=u32(raw(chpe-base,4)),DynamicValueRelocTableOffset=delta,DynamicValueRelocTableSection=section_index),dynamic_relocations=dict(file_offset=table,version=version,size_excludes_table_header=size,table_header_size=8,entries=entries),sections=sections)
(root/'arm64x-pe-metadata.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result,indent=2))

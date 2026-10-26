package main

import (
	"bytes"
	"debug/pe"
	"encoding/binary"
	"errors"
	"os"
)

// Windows SDK winnt.h supplies IMAGE_LOAD_CONFIG_DIRECTORY64 and packed DVRT
// headers. ARM64X fixup and CHPE code-map encodings are also implemented by LLVM:
// https://llvm.org/doxygen/COFFObjectFile_8cpp_source.html
// https://llvm.org/doxygen/Object_2COFF_8h_source.html
// This is bounded static validation of our MSVC ARM64X DLL, not load acceptance.
type arm64xEvidence struct {
	CHPEVersion              uint32   `json:"chpe_version"`
	CodeMapRanges            uint32   `json:"code_map_ranges"`
	NativeAndECCode          bool     `json:"native_and_ec_code"`
	DynamicRelocationVersion uint32   `json:"dynamic_relocation_version"`
	ARM64XEntries            int      `json:"arm64x_entries"`
	Fixups                   int      `json:"fixups"`
	MachineRewriteVerified   bool     `json:"machine_rewrite_verified"`
	ECImportedLibraries      []string `json:"ec_imported_libraries"`
}

type arm64xImage struct {
	file   *os.File
	pe     *pe.File
	header *pe.OptionalHeader64
	size   uint64
	hybrid []byte
}

func (im *arm64xImage) readOffset(offset, size uint64) ([]byte, error) {
	if size == 0 || size > 16*1024*1024 || offset > im.size || size > im.size-offset {
		return nil, errors.New("ARM64X metadata exceeds the file or bounded reader")
	}
	data := make([]byte, int(size))
	if _, err := im.file.ReadAt(data, int64(offset)); err != nil {
		return nil, err
	}
	return data, nil
}

func (im *arm64xImage) rvaOffset(rva uint32, size uint64) (uint64, error) {
	end := uint64(rva) + size
	if size == 0 || end > uint64(im.header.SizeOfImage) {
		return 0, errors.New("ARM64X RVA exceeds the image")
	}
	var offset uint64
	matches := 0
	if end <= uint64(im.header.SizeOfHeaders) {
		offset = uint64(rva)
		matches++
	}
	for _, s := range im.pe.Sections {
		if rva >= s.VirtualAddress && uint64(rva-s.VirtualAddress)+size <= uint64(s.Size) {
			offset = uint64(s.Offset) + uint64(rva-s.VirtualAddress)
			matches++
		}
	}
	if matches != 1 || offset > im.size || size > im.size-offset {
		return 0, errors.New("ARM64X RVA is unmapped, ambiguous or truncated")
	}
	return offset, nil
}

func (im *arm64xImage) readRVA(rva uint32, size uint64) ([]byte, error) {
	offset, err := im.rvaOffset(rva, size)
	if err != nil {
		return nil, err
	}
	return im.readOffset(offset, size)
}

func (im *arm64xImage) vaRVA(va uint64) (uint32, error) {
	if va < im.header.ImageBase || va-im.header.ImageBase > 0xffffffff || va-im.header.ImageBase >= uint64(im.header.SizeOfImage) {
		return 0, errors.New("ARM64X metadata VA is outside its image")
	}
	return uint32(va - im.header.ImageBase), nil
}

func inspectARM64X(path string) (*arm64xEvidence, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return nil, err
	}
	image, err := pe.NewFile(file)
	if err != nil {
		return nil, err
	}
	header, ok := image.OptionalHeader.(*pe.OptionalHeader64)
	if !ok || header.Magic != 0x20b || image.Machine != pe.IMAGE_FILE_MACHINE_ARM64 ||
		image.Characteristics&(pe.IMAGE_FILE_EXECUTABLE_IMAGE|pe.IMAGE_FILE_DLL) != pe.IMAGE_FILE_EXECUTABLE_IMAGE|pe.IMAGE_FILE_DLL {
		return nil, errors.New("shared TSF must be an ARM64 PE32+ DLL before ARM64X fixups")
	}
	if info.Size() < 64 || header.SizeOfHeaders < 64 || uint64(header.SizeOfHeaders) > uint64(info.Size()) ||
		header.SizeOfImage < header.SizeOfHeaders || len(image.Sections) == 0 || len(image.Sections) > 96 ||
		header.NumberOfRvaAndSizes <= pe.IMAGE_DIRECTORY_ENTRY_LOAD_CONFIG || header.NumberOfRvaAndSizes > 16 {
		return nil, errors.New("ARM64X image/header layout is invalid")
	}
	im := &arm64xImage{file: file, pe: image, header: header, size: uint64(info.Size())}
	// Apply fixups only to a bounded in-memory copy so the dependency audit can
	// inspect the second ABI's import directory without loading or editing it.
	im.hybrid, err = im.readOffset(0, im.size)
	if err != nil {
		return nil, err
	}
	for i, section := range image.Sections {
		span := max(section.Size, section.VirtualSize)
		if uint64(section.VirtualAddress)+uint64(span) > uint64(header.SizeOfImage) ||
			(section.Size > 0 && (section.Offset < header.SizeOfHeaders || uint64(section.Offset)+uint64(section.Size) > im.size)) {
			return nil, errors.New("ARM64X section exceeds image or file")
		}
		for _, other := range image.Sections[:i] {
			if section.Size > 0 && other.Size > 0 && uint64(section.Offset) < uint64(other.Offset)+uint64(other.Size) && uint64(other.Offset) < uint64(section.Offset)+uint64(section.Size) {
				return nil, errors.New("overlapping ARM64X file sections")
			}
			otherSpan := max(other.Size, other.VirtualSize)
			if span > 0 && otherSpan > 0 && uint64(section.VirtualAddress) < uint64(other.VirtualAddress)+uint64(otherSpan) && uint64(other.VirtualAddress) < uint64(section.VirtualAddress)+uint64(span) {
				return nil, errors.New("overlapping ARM64X virtual sections")
			}
		}
	}
	dos, err := im.readOffset(0, 64)
	if err != nil || binary.LittleEndian.Uint16(dos) != 0x5a4d {
		return nil, errors.New("ARM64X DOS header missing")
	}
	peOffset := binary.LittleEndian.Uint32(dos[0x3c:])
	if uint64(peOffset)+24+uint64(image.SizeOfOptionalHeader)+uint64(len(image.Sections))*40 > uint64(header.SizeOfHeaders) {
		return nil, errors.New("ARM64X PE/section headers exceed SizeOfHeaders")
	}
	machineRVA := peOffset + 4
	directory := header.DataDirectory[pe.IMAGE_DIRECTORY_ENTRY_LOAD_CONFIG]
	if directory.VirtualAddress == 0 || directory.Size < 232 {
		return nil, errors.New("ARM64X load configuration missing or too short")
	}
	config, err := im.readRVA(directory.VirtualAddress, uint64(directory.Size))
	if err != nil {
		return nil, err
	}
	if size := binary.LittleEndian.Uint32(config); size < 232 || size > directory.Size {
		return nil, errors.New("ARM64X load configuration declared size is invalid")
	}
	chpeRVA, err := im.vaRVA(binary.LittleEndian.Uint64(config[200:208]))
	if err != nil {
		return nil, err
	}
	chpe, err := im.readRVA(chpeRVA, 12)
	if err != nil {
		return nil, err
	}
	evidence := &arm64xEvidence{CHPEVersion: binary.LittleEndian.Uint32(chpe), CodeMapRanges: binary.LittleEndian.Uint32(chpe[8:])}
	if evidence.CHPEVersion != 2 || evidence.CodeMapRanges == 0 || evidence.CodeMapRanges > 4096 {
		return nil, errors.New("ARM64X CHPE metadata version/code-map count is unsupported")
	}
	codeMap, err := im.readRVA(binary.LittleEndian.Uint32(chpe[4:]), uint64(evidence.CodeMapRanges)*8)
	if err != nil {
		return nil, err
	}
	var native, ec bool
	var previousEnd uint64
	for pos := 0; pos < len(codeMap); pos += 8 {
		encoded := binary.LittleEndian.Uint32(codeMap[pos:])
		kind := encoded & 3
		start := encoded &^ 3
		length := binary.LittleEndian.Uint32(codeMap[pos+4:])
		end := uint64(start) + uint64(length)
		if kind > 2 || length == 0 || uint64(start) < previousEnd || end > uint64(header.SizeOfImage) {
			return nil, errors.New("invalid ARM64X CHPE code-map range")
		}
		// A classified range may span section alignment padding. Both ends must
		// still map to actual file bytes; no out-of-image code is accepted.
		if _, err = im.rvaOffset(start, 1); err != nil {
			return nil, err
		}
		if _, err = im.rvaOffset(uint32(end-1), 1); err != nil {
			return nil, err
		}
		previousEnd = end
		native = native || kind == 0
		ec = ec || kind == 1
	}
	if !native || !ec {
		return nil, errors.New("shared TSF CHPE map lacks native ARM64 or ARM64EC code")
	}
	evidence.NativeAndECCode = true
	var tableRVA uint32
	if va := binary.LittleEndian.Uint64(config[192:200]); va != 0 {
		tableRVA, err = im.vaRVA(va)
		if err != nil {
			return nil, err
		}
	}
	sectionIndex := binary.LittleEndian.Uint16(config[228:230])
	if sectionIndex != 0 {
		if int(sectionIndex) > len(image.Sections) {
			return nil, errors.New("ARM64X DVRT section index is invalid")
		}
		section := image.Sections[sectionIndex-1]
		offset := binary.LittleEndian.Uint32(config[224:228])
		if uint64(offset)+8 > uint64(section.Size) || uint64(section.VirtualAddress)+uint64(offset) > 0xffffffff {
			return nil, errors.New("ARM64X DVRT section offset is invalid")
		}
		sectionRVA := section.VirtualAddress + offset
		if tableRVA != 0 && tableRVA != sectionRVA {
			return nil, errors.New("ARM64X DVRT locators disagree")
		}
		tableRVA = sectionRVA
	}
	if tableRVA == 0 {
		return nil, errors.New("ARM64X dynamic relocation table missing")
	}
	tableHeader, err := im.readRVA(tableRVA, 8)
	if err != nil {
		return nil, err
	}
	evidence.DynamicRelocationVersion = binary.LittleEndian.Uint32(tableHeader)
	size := binary.LittleEndian.Uint32(tableHeader[4:])
	if evidence.DynamicRelocationVersion != 1 || size < 12 || uint64(tableRVA)+8+uint64(size) > uint64(header.SizeOfImage) {
		return nil, errors.New("ARM64X DVRT version/size is invalid")
	}
	table, err := im.readRVA(tableRVA+8, uint64(size))
	if err != nil {
		return nil, err
	}
	for pos := 0; pos < len(table); {
		if len(table)-pos < 12 {
			return nil, errors.New("truncated ARM64X DVRT entry")
		}
		symbol := binary.LittleEndian.Uint64(table[pos:])
		payloadSize := binary.LittleEndian.Uint32(table[pos+8:])
		pos += 12
		if payloadSize == 0 || uint64(payloadSize) > uint64(len(table)-pos) {
			return nil, errors.New("ARM64X DVRT payload size is invalid")
		}
		if symbol == 6 {
			evidence.ARM64XEntries++
			if err = im.checkFixups(table[pos:pos+int(payloadSize)], machineRVA, evidence); err != nil {
				return nil, err
			}
		}
		pos += int(payloadSize)
	}
	if evidence.ARM64XEntries == 0 || evidence.Fixups == 0 || !evidence.MachineRewriteVerified {
		return nil, errors.New("ARM64X relocation entry or AMD64 machine rewrite is missing")
	}
	ecView, err := pe.NewFile(bytes.NewReader(im.hybrid))
	if err != nil {
		return nil, errors.New("ARM64X fixups produced an invalid EC PE view")
	}
	if ecView.Machine != pe.IMAGE_FILE_MACHINE_AMD64 {
		return nil, errors.New("ARM64X EC view has the wrong machine")
	}
	ecHeader, ok := ecView.OptionalHeader.(*pe.OptionalHeader64)
	if !ok || ecHeader.SizeOfImage != header.SizeOfImage || ecHeader.SizeOfHeaders != header.SizeOfHeaders || ecHeader.NumberOfRvaAndSizes > 16 || len(ecView.Sections) != len(image.Sections) {
		return nil, errors.New("ARM64X EC view changes the image layout")
	}
	for i, section := range ecView.Sections {
		if section.SectionHeader != image.Sections[i].SectionHeader {
			return nil, errors.New("ARM64X fixups change section layout")
		}
	}
	evidence.ECImportedLibraries, err = importedLibraries(ecView)
	if err != nil {
		return nil, err
	}
	return evidence, nil
}

func (im *arm64xImage) checkFixups(data []byte, machineRVA uint32, evidence *arm64xEvidence) error {
	for pos := 0; pos < len(data); {
		if len(data)-pos < 8 {
			return errors.New("truncated ARM64X fixup block")
		}
		page := binary.LittleEndian.Uint32(data[pos:])
		size := binary.LittleEndian.Uint32(data[pos+4:])
		if page&4095 != 0 || size <= 8 || size%4 != 0 || uint64(size) > uint64(len(data)-pos) {
			return errors.New("invalid ARM64X fixup block bounds")
		}
		end := pos + int(size)
		for at := pos + 8; at < end; {
			token := binary.LittleEndian.Uint16(data[at:])
			at += 2
			if token == 0 {
				if at != end {
					return errors.New("ARM64X fixup padding is not final")
				}
				break
			}
			kind := (token >> 12) & 3
			arg := token >> 14
			width := uint64(1) << arg
			extra := 0
			switch kind {
			case 0:
			case 1:
				if arg == 0 {
					return errors.New("ARM64X VALUE fixup has invalid width")
				}
				extra = int(width)
			case 2:
				width = 4
				extra = 2
			default:
				return errors.New("unknown ARM64X fixup type")
			}
			if at+extra > end {
				return errors.New("truncated ARM64X fixup value")
			}
			target := uint64(page) + uint64(token&4095)
			if target > 0xffffffff || target%width != 0 {
				return errors.New("invalid ARM64X fixup target")
			}
			offset, err := im.rvaOffset(uint32(target), width)
			if err != nil {
				return err
			}
			if target < uint64(machineRVA)+2 && target+width > uint64(machineRVA) {
				if target != uint64(machineRVA) || kind != 1 || width != 2 || binary.LittleEndian.Uint16(data[at:]) != pe.IMAGE_FILE_MACHINE_AMD64 || evidence.MachineRewriteVerified {
					return errors.New("ARM64X machine rewrite is ambiguous or invalid")
				}
				evidence.MachineRewriteVerified = true
			}
			view := im.hybrid[int(offset):int(offset+width)]
			switch kind {
			case 0:
				clear(view)
			case 1:
				copy(view, data[at:at+extra])
			case 2:
				delta := int64(binary.LittleEndian.Uint16(data[at:]))
				if arg&1 != 0 {
					delta = -delta
				}
				if arg&2 != 0 {
					delta *= 8
				} else {
					delta *= 4
				}
				binary.LittleEndian.PutUint32(view, uint32(int64(binary.LittleEndian.Uint32(view))+delta))
			}
			at += extra
			evidence.Fixups++
		}
		pos = end
	}
	return nil
}

package main

import (
	"bytes"
	"debug/pe"
	"encoding/binary"
	"os"
	"path/filepath"
	"testing"
)

const arm64xFixturePEOffset = 0x80
const arm64xFixtureOptional = arm64xFixturePEOffset + 24
const arm64xFixtureLoadDirectory = arm64xFixtureOptional + 112 + pe.IMAGE_DIRECTORY_ENTRY_LOAD_CONFIG*8

// Structurally complete metadata with tiny inert code ranges. Never executable
// test content: these bytes only exercise the independent static parser.
func arm64xFixture(t *testing.T) []byte {
	t.Helper()
	data := make([]byte, 0xe00)
	put16 := func(offset int, value uint16) { binary.LittleEndian.PutUint16(data[offset:], value) }
	put32 := func(offset int, value uint32) { binary.LittleEndian.PutUint32(data[offset:], value) }
	put64 := func(offset int, value uint64) { binary.LittleEndian.PutUint64(data[offset:], value) }
	put16(0, 0x5a4d)
	put32(0x3c, arm64xFixturePEOffset)
	put32(arm64xFixturePEOffset, 0x4550)
	var header bytes.Buffer
	if err := binary.Write(&header, binary.LittleEndian, pe.FileHeader{Machine: pe.IMAGE_FILE_MACHINE_ARM64, NumberOfSections: 1, SizeOfOptionalHeader: 240, Characteristics: pe.IMAGE_FILE_EXECUTABLE_IMAGE | pe.IMAGE_FILE_DLL}); err != nil {
		t.Fatal(err)
	}
	copy(data[arm64xFixturePEOffset+4:], header.Bytes())
	optional := pe.OptionalHeader64{Magic: 0x20b, ImageBase: 0x180000000, SectionAlignment: 0x1000, FileAlignment: 0x200, SizeOfImage: 0x2000, SizeOfHeaders: 0x400, NumberOfRvaAndSizes: 16}
	optional.DataDirectory[pe.IMAGE_DIRECTORY_ENTRY_LOAD_CONFIG] = pe.DataDirectory{VirtualAddress: 0x1000, Size: 232}
	header.Reset()
	if err := binary.Write(&header, binary.LittleEndian, optional); err != nil {
		t.Fatal(err)
	}
	copy(data[arm64xFixtureOptional:], header.Bytes())
	section := arm64xFixtureOptional + 240
	copy(data[section:], []byte(".fixture"))
	put32(section+8, 0xa00)
	put32(section+12, 0x1000)
	put32(section+16, 0xa00)
	put32(section+20, 0x400)
	put32(section+36, pe.IMAGE_SCN_CNT_CODE|pe.IMAGE_SCN_MEM_READ|pe.IMAGE_SCN_MEM_EXECUTE)
	put32(0x400, 232)
	put64(0x400+200, optional.ImageBase+0x1100)
	put32(0x400+224, 0x200)
	put16(0x400+228, 1)
	put32(0x500, 2)
	put32(0x504, 0x1140)
	put32(0x508, 2)
	put32(0x540, 0x1400)
	put32(0x544, 16)
	put32(0x548, 0x1421)
	put32(0x54c, 16)
	put32(0x600, 1)
	put32(0x604, 24)
	put64(0x608, 6)
	put32(0x610, 12)
	put32(0x614, 0)
	put32(0x618, 12)
	put16(0x61c, 0x5000|arm64xFixturePEOffset+4)
	put16(0x61e, pe.IMAGE_FILE_MACHINE_AMD64)
	return data
}

func writeARM64XFixture(t *testing.T, data []byte) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "static-never-loaded.dll")
	if err := os.WriteFile(path, data, 0600); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestARM64XStaticMetadataAndLegacyBoundary(t *testing.T) {
	data := arm64xFixture(t)
	path := writeARM64XFixture(t, data)
	result, err := inspectProductPE(path, "arm64/YimeTextServiceExperiment.dll", arm64InstallableContract)
	if err != nil {
		t.Fatal(err)
	}
	if result.Machine != "arm64" || result.ARM64X == nil || !result.ARM64X.NativeAndECCode || !result.ARM64X.MachineRewriteVerified || result.ARM64X.ARM64XEntries != 1 || result.ARM64X.Fixups != 1 {
		t.Fatalf("missing parsed ARM64X evidence: %+v", result)
	}
	after, err := os.ReadFile(path)
	if err != nil || !bytes.Equal(data, after) {
		t.Fatal("static audit changed the input")
	}
	binary.LittleEndian.PutUint32(data[arm64xFixtureLoadDirectory:], 0)
	path = writeARM64XFixture(t, data)
	if _, err = inspectProductPE(path, "arm64/YimeTextServiceExperiment.dll", arm64InstallableContract); err == nil {
		t.Fatal("pure ARM64 accepted as shared TSF")
	}
	if _, err = inspectProductPE(path, "arm64/YimeTextServiceRegistration.exe", arm64InstallableContract); err != nil {
		t.Fatal("plain native registration tool incorrectly requires ARM64X", err)
	}
	if _, err = inspectProductPE(path, "x64/YimeTextServiceExperiment.dll", localInstallableContract); err != nil {
		t.Fatal("legacy inspection acquired an ARM64X requirement", err)
	}
}

func TestARM64XRejectsSingleABIAndMalformedMetadata(t *testing.T) {
	for _, tc := range []struct {
		name   string
		mutate func([]byte)
	}{
		{"arm64ec", func(d []byte) { binary.LittleEndian.PutUint16(d[arm64xFixturePEOffset+4:], 0xa641) }},
		{"amd64_ec_view", func(d []byte) {
			binary.LittleEndian.PutUint16(d[arm64xFixturePEOffset+4:], pe.IMAGE_FILE_MACHINE_AMD64)
		}},
		{"not_dll", func(d []byte) {
			binary.LittleEndian.PutUint16(d[arm64xFixturePEOffset+22:], pe.IMAGE_FILE_EXECUTABLE_IMAGE)
		}},
		{"short_directory", func(d []byte) { binary.LittleEndian.PutUint32(d[arm64xFixtureLoadDirectory+4:], 231) }},
		{"short_load_config", func(d []byte) { binary.LittleEndian.PutUint32(d[0x400:], 231) }},
		{"oversized_load_config", func(d []byte) { binary.LittleEndian.PutUint32(d[0x400:], 233) }},
		{"load_rva_overflow", func(d []byte) { binary.LittleEndian.PutUint32(d[arm64xFixtureLoadDirectory:], 0xfffffff0) }},
		{"zero_chpe", func(d []byte) { binary.LittleEndian.PutUint64(d[0x400+200:], 0) }},
		{"chpe_outside_image", func(d []byte) { binary.LittleEndian.PutUint64(d[0x400+200:], 0x180002001) }},
		{"unknown_chpe_version", func(d []byte) { binary.LittleEndian.PutUint32(d[0x500:], 3) }},
		{"zero_code_map", func(d []byte) { binary.LittleEndian.PutUint32(d[0x508:], 0) }},
		{"oversized_code_map", func(d []byte) { binary.LittleEndian.PutUint32(d[0x508:], 4097) }},
		{"unmapped_code_map", func(d []byte) { binary.LittleEndian.PutUint32(d[0x504:], 0x1fff) }},
		{"ec_only", func(d []byte) { binary.LittleEndian.PutUint32(d[0x540:], 0x1401) }},
		{"native_only", func(d []byte) { binary.LittleEndian.PutUint32(d[0x548:], 0x1420) }},
		{"unknown_code_kind", func(d []byte) { binary.LittleEndian.PutUint32(d[0x548:], 0x1423) }},
		{"invalid_dvrt_section", func(d []byte) { binary.LittleEndian.PutUint16(d[0x400+228:], 2) }},
		{"invalid_dvrt_offset", func(d []byte) { binary.LittleEndian.PutUint32(d[0x400+224:], 0xa00) }},
		{"conflicting_dvrt_locators", func(d []byte) { binary.LittleEndian.PutUint64(d[0x400+192:], 0x180001208) }},
		{"unknown_dvrt_version", func(d []byte) { binary.LittleEndian.PutUint32(d[0x600:], 2) }},
		{"zero_dvrt_size", func(d []byte) { binary.LittleEndian.PutUint32(d[0x604:], 0) }},
		{"oversized_dvrt", func(d []byte) { binary.LittleEndian.PutUint32(d[0x604:], 0xffffffff) }},
		{"not_arm64x_symbol", func(d []byte) { binary.LittleEndian.PutUint64(d[0x608:], 4) }},
		{"empty_fixups", func(d []byte) { binary.LittleEndian.PutUint32(d[0x610:], 0) }},
		{"truncated_fixups", func(d []byte) { binary.LittleEndian.PutUint32(d[0x610:], 13) }},
		{"unaligned_page", func(d []byte) { binary.LittleEndian.PutUint32(d[0x614:], 1) }},
		{"bad_block_size", func(d []byte) { binary.LittleEndian.PutUint32(d[0x618:], 10) }},
		{"unknown_fixup", func(d []byte) { binary.LittleEndian.PutUint16(d[0x61c:], 0x7084) }},
		{"truncated_value", func(d []byte) { binary.LittleEndian.PutUint16(d[0x61c:], 0xd084) }},
		{"invalid_value_width", func(d []byte) { binary.LittleEndian.PutUint16(d[0x61c:], 0x1084) }},
		{"wrong_machine_rewrite", func(d []byte) { binary.LittleEndian.PutUint16(d[0x61e:], pe.IMAGE_FILE_MACHINE_ARM64) }},
		{"no_machine_rewrite", func(d []byte) { binary.LittleEndian.PutUint16(d[0x61c:], 0x5094) }},
		{"truncated_section", func(d []byte) { binary.LittleEndian.PutUint32(d[arm64xFixtureOptional+240+16:], 0xa01) }},
		{"overlapping_sections", func(d []byte) {
			binary.LittleEndian.PutUint16(d[arm64xFixturePEOffset+6:], 2)
			start := arm64xFixtureOptional + 240
			copy(d[start+40:start+80], d[start:start+40])
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			data := arm64xFixture(t)
			tc.mutate(data)
			if _, err := inspectARM64X(writeARM64XFixture(t, data)); err == nil {
				t.Fatal("malformed or single-ABI DLL passed ARM64X gate")
			}
		})
	}
}

func TestARM64XAuditsBothImportViews(t *testing.T) {
	data := arm64xFixture(t)
	put32 := func(offset int, value uint32) { binary.LittleEndian.PutUint32(data[offset:], value) }
	importField := arm64xFixtureOptional + 112 + pe.IMAGE_DIRECTORY_ENTRY_IMPORT*8
	put32(importField, 0x1500)
	put32(importField+4, 40)
	put32(0x900, 0x15c0)
	put32(0x90c, 0x1580)
	put32(0x910, 0x15c0)
	copy(data[0x980:], []byte("KERNEL32.dll\x00"))
	put32(0xa00, 0x16c0)
	put32(0xa0c, 0x1680)
	put32(0xa10, 0x16c0)
	copy(data[0xa80:], []byte("rime.dll\x00"))
	put32(0x604, 32)
	put32(0x610, 20)
	put32(0x618, 20)
	binary.LittleEndian.PutUint16(data[0x620:], uint16(0x9000|importField))
	put32(0x622, 0x1600)
	result, err := inspectProductPE(writeARM64XFixture(t, data), "arm64/YimeTextServiceExperiment.dll", arm64InstallableContract)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Libraries) != 2 || result.Libraries[0] != "kernel32.dll" || result.Libraries[1] != "rime.dll" || !containsForbiddenToken(result.Libraries[1]) {
		t.Fatalf("EC-only dependency escaped combined audit: %+v", result)
	}
}

func TestARM64XIdentifiedNativeBuild(t *testing.T) {
	path := os.Getenv("YIME_ARM64X_PE_TEST_PATH")
	if path == "" {
		t.Skip("explicit native build path not supplied; synthetic parser cases only")
	}
	result, err := inspectProductPE(path, "arm64/YimeTextServiceExperiment.dll", arm64InstallableContract)
	if err != nil {
		t.Fatal(err)
	}
	if result.ARM64X == nil || !result.ARM64X.MachineRewriteVerified {
		t.Fatal("real DLL lacks verified dual-view metadata")
	}
	t.Logf("native ARM64X static evidence: %+v", result.ARM64X)
}

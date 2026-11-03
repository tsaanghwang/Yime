package main

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Build under a unique protected sibling and publish only after full validation.
// Failed staging directories remain attributable evidence and never poison the
// final plan identity. The caller validates an already-published stage too.
func publishStage(cache, identity string, create, fill, verify func(string) error, rename func(string, string) error) (string, error) {
	if !hashPattern.MatchString(identity) {
		return "", errors.New("invalid cache identity")
	}
	final := filepath.Join(cache, identity)
	if st, err := os.Lstat(final); err == nil {
		if !st.IsDir() || st.Mode()&os.ModeSymlink != 0 {
			return "", errors.New("published cache is not a plain directory")
		}
		return final, nil
	} else if !os.IsNotExist(err) {
		return "", err
	}
	var nonce [16]byte
	if _, err := rand.Read(nonce[:]); err != nil {
		return "", err
	}
	temp := filepath.Join(cache, identity+".staging-"+hex.EncodeToString(nonce[:]))
	if err := create(temp); err != nil {
		return "", err
	}
	for _, operation := range []func(string) error{fill, verify} {
		if err := operation(temp); err != nil {
			return "", fmt.Errorf("preserved incomplete staging %s: %w", temp, err)
		}
	}
	if err := rename(temp, final); err != nil {
		// A competing completed publication is validated by the caller. Keep
		// our complete temporary sibling; never replace another publication.
		if st, statErr := os.Lstat(final); statErr == nil && st.IsDir() && st.Mode()&os.ModeSymlink == 0 {
			return final, nil
		}
		return "", fmt.Errorf("preserved complete staging %s: %w", temp, err)
	}
	return final, nil
}

func insideDirectory(path, root string) bool {
	path, root = filepath.Clean(path), filepath.Clean(root)
	return strings.EqualFold(path, root) || strings.HasPrefix(strings.ToLower(path), strings.ToLower(root+string(os.PathSeparator)))
}

func mutatingAccessMask(content bool) uint32 {
	mask := uint32(0x40000000 | 0x10000000 | 0x10000 | 0x40000 | 0x80000 | 0x40 | 0x10 | 0x100)
	if content {
		mask |= 2 | 4 // AddFile/WriteData and AddSubdirectory/AppendData.
	}
	return mask
}

type runtimeSpec struct {
	directory, executable, manifest string
}

func productRuntime(product string) (runtimeSpec, error) {
	switch product {
	case "yimecore-18u":
		return runtimeSpec{"YimeCore 18u Touch", "bin/Yime18uInstalledRuntime.exe", "installed-18u-product.json"}, nil
	case "rime-pime":
		return runtimeSpec{"Yime Rime-PIME", "PIMELauncher.exe", ""}, nil
	default:
		return runtimeSpec{}, errors.New("unsupported runtime product")
	}
}

func runtimeArguments(spec runtimeSpec, installRoot, manifestHash string) ([]string, error) {
	if spec.manifest == "" {
		return nil, nil
	}
	if !hashPattern.MatchString(manifestHash) {
		return nil, errors.New("checked installed manifest hash is required")
	}
	return []string{"--installed-18u-run", "--install-root", installRoot, "--manifest-sha256", manifestHash}, nil
}

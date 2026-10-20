package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// Set only by the portable builder. A package's resource inventory is bound to
// its executable, not trusted merely because a neighbouring JSON says so.
var portableResourcesSHA256 string

type portableResources struct {
	SchemaVersion int               `json:"schemaVersion"`
	Scope         string            `json:"scope"`
	Files         map[string]string `json:"files"`
}

func verifyPortableResources(root, expected string) (portableResources, error) {
	var r portableResources
	body, err := os.ReadFile(filepath.Join(root, "resources.json"))
	if err != nil {
		return r, fmt.Errorf("便携资源清单缺失: %w", err)
	}
	sum := sha256.Sum256(body)
	if hex.EncodeToString(sum[:]) != expected {
		return r, fmt.Errorf("便携资源清单与程序不匹配；请完整重新解压同一包")
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return r, err
	}
	if r.SchemaVersion != 1 || r.Scope != "isolated-cn134-portable-resources" || len(r.Files) == 0 {
		return r, fmt.Errorf("无效便携资源清单")
	}
	root, err = filepath.EvalSymlinks(root)
	if err != nil {
		return r, err
	}
	for name, want := range r.Files {
		if !filepath.IsLocal(name) || strings.Contains(name, "\\") {
			return r, fmt.Errorf("无效包内路径: %s", name)
		}
		path, err := filepath.EvalSymlinks(filepath.Join(root, filepath.FromSlash(name)))
		if err != nil {
			return r, fmt.Errorf("便携资源缺失 %s: %w", name, err)
		}
		rel, err := filepath.Rel(root, path)
		if err != nil || !filepath.IsLocal(rel) {
			return r, fmt.Errorf("便携资源越出包目录: %s", name)
		}
		f, err := os.Open(path)
		if err != nil {
			return r, err
		}
		h := sha256.New()
		_, copyErr := io.Copy(h, f)
		closeErr := f.Close()
		if copyErr != nil || closeErr != nil || hex.EncodeToString(h.Sum(nil)) != want {
			return r, fmt.Errorf("便携资源校验失败: %s", name)
		}
	}
	return r, nil
}

func samePortablePath(a, b string) bool {
	a, ea := filepath.EvalSymlinks(a)
	b, eb := filepath.EvalSymlinks(b)
	if ea != nil || eb != nil {
		return false
	}
	infoA, ea := os.Stat(a)
	infoB, eb := os.Stat(b)
	return ea == nil && eb == nil && os.SameFile(infoA, infoB)
}

func preparePortable(o *options, root, expected string) error {
	if expected == "" {
		if o.CheckPackage {
			return fmt.Errorf("--check-package requires a complete portable build")
		}
		if o.Root == "" {
			o.Root = ".."
		}
		return nil
	}
	r, err := verifyPortableResources(root, expected)
	if err != nil {
		return err
	}
	if o.Root != "" && !samePortablePath(o.Root, root) {
		return fmt.Errorf("便携程序只使用自身目录资源，不接受外部 --root")
	}
	o.Root = root
	if o.CheckPackage {
		o.CheckData = true
	}
	if !o.EnglishOnly && !o.Preview && !o.CheckData && !o.Smoke && o.Shot == "" {
		o.Host = true
	}
	if o.Host || o.Preview || o.CheckData {
		data := filepath.Join(root, "data")
		if o.DataDir != "" && !samePortablePath(o.DataDir, data) {
			return fmt.Errorf("便携程序只使用包内完整词典，不接受外部 --data-dir")
		}
		o.DataDir = data
	}
	if o.Profile == "" && !o.GeometryExplicit && o.Zones == "both" && !o.Gutters {
		o.Profile = "prototypes/touch-terminal/desktop/profiles/main-only.json"
	}
	if o.Profile != "" {
		path := o.Profile
		if !filepath.IsAbs(path) {
			path = filepath.Join(root, path)
		}
		rel, err := filepath.Rel(root, path)
		if err != nil || !filepath.IsLocal(rel) || r.Files[filepath.ToSlash(rel)] == "" {
			return fmt.Errorf("便携程序只接受已校验的包内 profile")
		}
		o.Profile = path
	}
	return nil
}

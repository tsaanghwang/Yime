package yimecore

import (
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

func TestExperimentalCoreKeepsHostDependencyBoundary(t *testing.T) {
	for _, dir := range []string{".", filepath.Join("..", "engineapi")} {
		entries, err := os.ReadDir(dir)
		if err != nil {
			t.Fatal(err)
		}
		for _, entry := range entries {
			if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".go") || strings.HasSuffix(entry.Name(), "_test.go") {
				continue
			}
			path := filepath.Join(dir, entry.Name())
			file, err := parser.ParseFile(token.NewFileSet(), path, nil, parser.ImportsOnly)
			if err != nil {
				t.Fatal(err)
			}
			for _, spec := range file.Decls {
				declaration, ok := spec.(*ast.GenDecl)
				if !ok {
					continue
				}
				for _, item := range declaration.Specs {
					importSpec, ok := item.(*ast.ImportSpec)
					if !ok {
						continue
					}
					importPath, err := strconv.Unquote(importSpec.Path.Value)
					if err != nil {
						t.Fatal(err)
					}
					for _, forbidden := range []string{"/pime", "librime", "native_cgo", "win32ui"} {
						if strings.Contains(importPath, forbidden) {
							t.Fatalf("%s imports forbidden host dependency %q", path, importPath)
						}
					}
					if importPath == "C" {
						t.Fatalf("%s imports cgo", path)
					}
				}
			}
		}
	}
}

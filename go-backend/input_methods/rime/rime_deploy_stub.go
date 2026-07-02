//go:build !windows

package rime

func deploySchemaConfig(schemaPath string) bool {
	return schemaPath != ""
}

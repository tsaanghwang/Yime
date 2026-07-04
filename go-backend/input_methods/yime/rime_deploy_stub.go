//go:build !windows

package yime

func deploySchemaConfig(schemaPath string) bool {
	return schemaPath != ""
}

func deployDefaultCustomConfig(configPath string) bool {
	return configPath != ""
}

func deploySchemaCustomConfig(configPath string) bool {
	return configPath != ""
}

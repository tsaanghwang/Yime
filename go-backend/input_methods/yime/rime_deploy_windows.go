//go:build windows

package yime

func deploySchemaConfig(schemaPath string) bool {
	return DeployConfigFile(schemaPath, "schema")
}

func deployDefaultCustomConfig(configPath string) bool {
	return DeployConfigFile(configPath, "config_version")
}

func deploySchemaCustomConfig(configPath string) bool {
	return DeployConfigFile(configPath, "schema")
}

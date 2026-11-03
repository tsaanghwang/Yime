package installed18uhost

type architectureContract struct{ directory, descriptor, productDescriptor string }

func contractForArch(arch string) architectureContract {
	switch arch {
	case "amd64":
		return architectureContract{"x64", "native-x64", "18u-touch-product.json"}
	case "arm64":
		return architectureContract{"arm64", "native-arm64", "18u-touch-product-arm64.json"}
	default:
		return architectureContract{}
	}
}

package touchbroker

// matchesProductArchitecture never accepts a descriptor for a different target.
func matchesProductArchitecture(goarch, descriptor string) bool {
 switch goarch { case "amd64": return descriptor == "x64"; case "arm64": return descriptor == "arm64"; default: return false }
}

func productDescriptorPath(goarch string) string {
 switch goarch { case "amd64": return "tools/yimecore/18u-touch-product.json"; case "arm64": return "tools/yimecore/18u-touch-product-arm64.json"; default: return "" }
}

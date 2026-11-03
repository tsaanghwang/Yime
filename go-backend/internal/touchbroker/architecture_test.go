package touchbroker

import "testing"

func TestMatchesProductArchitecture(t *testing.T) {
	for _, c := range []struct {
		goarch, descriptor, path string
		want                     bool
	}{
		{"amd64", "x64", "tools/yimecore/18u-touch-product.json", true},
		{"arm64", "arm64", "tools/yimecore/18u-touch-product-arm64.json", true},
		{"arm64", "x64", "tools/yimecore/18u-touch-product-arm64.json", false},
		{"amd64", "arm64", "tools/yimecore/18u-touch-product.json", false},
		{"386", "x64", "", false}, {"arm64", "arm64x", "tools/yimecore/18u-touch-product-arm64.json", false},
	} {
		if got := matchesProductArchitecture(c.goarch, c.descriptor); got != c.want {
			t.Errorf("%+v: got %v", c, got)
		}
		if got := productDescriptorPath(c.goarch); got != c.path {
			t.Errorf("%+v: path %q", c, got)
		}
	}
}

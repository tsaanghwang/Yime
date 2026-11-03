package installed18uhost

import (
	"runtime"
	"testing"
)

func TestContractForArch(t *testing.T) {
	for _, c := range []struct{ arch, dir, descriptor, productDescriptor string }{
		{"amd64", "x64", "native-x64", "18u-touch-product.json"},
		{"arm64", "arm64", "native-arm64", "18u-touch-product-arm64.json"},
		{"386", "", "", ""}, {"arm64ec", "", "", ""},
	} {
		got := contractForArch(c.arch)
		if got.directory != c.dir || got.descriptor != c.descriptor || got.productDescriptor != c.productDescriptor {
			t.Errorf("%s: %+v", c.arch, got)
		}
	}
}

func TestCompiledTargetMatchesContract(t *testing.T) {
	c := contractForArch(runtime.GOARCH)
	if c.directory != nativeDirectory || c.descriptor != nativeDescriptor || c.productDescriptor != nativeProductDescriptor {
		t.Fatalf("compiled target differs from contract")
	}
}

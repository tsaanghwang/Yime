package yimebroker

import "testing"

func TestConnectionLimiterBoundsAndReleases(t *testing.T) {
	limiter := newConnectionLimiter(3, 2)
	releaseA, ok := limiter.acquire("a")
	if !ok {
		t.Fatal("first connection rejected")
	}
	releaseB, ok := limiter.acquire("a")
	if !ok {
		t.Fatal("second connection rejected")
	}
	if _, ok := limiter.acquire("a"); ok {
		t.Fatal("per-client limit not enforced")
	}
	releaseC, ok := limiter.acquire("b")
	if !ok {
		t.Fatal("third global connection rejected")
	}
	if _, ok := limiter.acquire("c"); ok {
		t.Fatal("global limit not enforced")
	}
	releaseA()
	releaseA()
	if release, ok := limiter.acquire("a"); !ok {
		t.Fatal("released capacity was not restored")
	} else {
		release()
	}
	releaseB()
	releaseC()
}

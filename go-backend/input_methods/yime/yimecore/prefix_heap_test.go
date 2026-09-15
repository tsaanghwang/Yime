package yimecore

import (
	"fmt"
	"math/rand"
	"reflect"
	"sort"
	"testing"
)

func TestFilePrefixHeapMatchesOriginalOrdering(t *testing.T) {
	random := rand.New(rand.NewSource(905))
	var records []fileRecord
	for i := 0; i < 1200; i++ {
		code := fmt.Sprintf("a%03d", i%111)
		if i%17 == 0 {
			code = "a"
		}
		if i%23 == 0 {
			code += "long"
		}
		records = append(records, fileRecord{code: []byte(code), text: []byte(fmt.Sprintf("词%04d", i)), weight: int64(random.Intn(11))})
	}
	for _, limit := range []int{1, 5, 10, 64, 65, 127, 512, 1200, 2000} {
		for round := 0; round < 3; round++ {
			random.Shuffle(len(records), func(i, j int) { records[i], records[j] = records[j], records[i] })
			var heap, oracle []fileRecord
			for _, item := range records {
				heap = insertFileHeap(heap, item, []byte("a"), limit)
				oracle = insertFileTop(oracle, item, []byte("a"), limit)
			}
			sort.Slice(heap, func(i, j int) bool { return betterFileRecord(heap[i], heap[j], []byte("a")) })
			if !reflect.DeepEqual(heap, oracle) {
				t.Fatalf("ordering changed at limit %d round %d", limit, round)
			}
		}
	}
}

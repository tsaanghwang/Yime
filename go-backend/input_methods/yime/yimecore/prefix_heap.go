package yimecore

// insertFileHeap retains exactly the same top K as insertFileTop, but keeps
// the worst retained record at the root. Large prefix windows (up to 4096 in
// first-syllable filtering) must not pay O(K) shifts for each matching record.
// The caller sorts the final K records with betterFileRecord before publishing.
func insertFileHeap(top []fileRecord, item fileRecord, input []byte, limit int) []fileRecord {
	if limit <= 0 {
		return nil
	}
	if len(top) < limit {
		top = append(top, item)
		for child := len(top) - 1; child > 0; {
			parent := (child - 1) / 2
			if !betterFileRecord(top[parent], top[child], input) {
				break
			}
			top[parent], top[child] = top[child], top[parent]
			child = parent
		}
		return top
	}
	if !betterFileRecord(item, top[0], input) {
		return top
	}
	top[0] = item
	for parent := 0; ; {
		child := 2*parent + 1
		if child >= len(top) {
			break
		}
		if child+1 < len(top) && betterFileRecord(top[child], top[child+1], input) {
			child++
		}
		if !betterFileRecord(top[parent], top[child], input) {
			break
		}
		top[parent], top[child] = top[child], top[parent]
		parent = child
	}
	return top
}

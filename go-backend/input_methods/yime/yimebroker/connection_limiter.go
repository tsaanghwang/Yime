package yimebroker

import "sync"

type connectionLimiter struct {
	mu           sync.Mutex
	total        int
	byClient     map[string]int
	maxTotal     int
	maxPerClient int
}

func newConnectionLimiter(maxTotal, maxPerClient int) *connectionLimiter {
	return &connectionLimiter{
		byClient: make(map[string]int), maxTotal: maxTotal, maxPerClient: maxPerClient,
	}
}

func (l *connectionLimiter) acquire(clientID string) (func(), bool) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.total >= l.maxTotal || l.byClient[clientID] >= l.maxPerClient {
		return nil, false
	}
	l.total++
	l.byClient[clientID]++
	var once sync.Once
	return func() {
		once.Do(func() {
			l.mu.Lock()
			defer l.mu.Unlock()
			l.total--
			l.byClient[clientID]--
			if l.byClient[clientID] == 0 {
				delete(l.byClient, clientID)
			}
		})
	}, true
}

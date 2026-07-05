//go:build windows

package yime

import (
	"log"
	"sync"

	"github.com/EasyIME/pime-go/pime"
)

type nativeBackend struct {
	sessionID RimeSessionId
}

var (
	rimeInitOnce sync.Once
	rimeInitOK   bool
)

func newNativeBackend() rimeBackend {
	return &nativeBackend{}
}

func (b *nativeBackend) Initialize(sharedDir, userDir string, firstRun bool) bool {
	rimeInitOnce.Do(func() {
		rimeInitOK = RimeInit(sharedDir, userDir, APP, APP_VERSION, firstRun)
		if !rimeInitOK {
			log.Println("RIME 初始化失败，原生后端不可用")
		}
	})
	return rimeInitOK
}

func (b *nativeBackend) EnsureSession() bool {
	if b.sessionID != 0 && FindSession(b.sessionID) {
		return true
	}
	sessionID, ok := StartSession()
	if ok {
		b.sessionID = sessionID
	}
	return ok
}

func (b *nativeBackend) DestroySession() {
	if b.sessionID != 0 {
		EndSession(b.sessionID)
		b.sessionID = 0
	}
}

func (b *nativeBackend) ClearComposition() {
	if b.sessionID != 0 {
		ClearComposition(b.sessionID)
	}
}

func (b *nativeBackend) ProcessKey(req *pime.Request, translatedKeyCode, modifiers int) bool {
	if !b.EnsureSession() {
		return false
	}
	return ProcessKey(b.sessionID, translatedKeyCode, modifiers)
}

func (b *nativeBackend) SelectCandidate(index int) bool {
	if !b.EnsureSession() {
		return false
	}
	return SelectCandidate(b.sessionID, index)
}

func (b *nativeBackend) UsesBackendCandidatePaging() bool {
	// Native Rime owns paging for real sessions. Do not switch this to Go-side
	// paging to force candidate counts; doing so can destabilize activation and
	// language-bar/menu click paths in host applications.
	return true
}

func (b *nativeBackend) State() rimeState {
	state := rimeState{}
	if b.sessionID == 0 {
		return state
	}
	if commit, ok := GetCommit(b.sessionID); ok {
		state.CommitString = commit.Text
	}
	if composition, ok := GetComposition(b.sessionID); ok {
		state.Composition = composition.Preedit
		state.CursorPos = composition.CursorPos
		state.SelStart = composition.SelStart
		state.SelEnd = composition.SelEnd
	}
	if menu, ok := GetMenu(b.sessionID); ok {
		candidates := make([]candidateItem, 0, len(menu.Candidates))
		for _, candidate := range menu.Candidates {
			candidates = append(candidates, candidateItem{
				Text:    candidate.Text,
				Comment: candidate.Comment,
			})
		}
		state.Candidates = candidates
		state.CandidateCursor = menu.HighlightedCandidateIndex
		state.SelectKeys = menu.SelectKeys
		state.PageSize = menu.PageSize
	}
	state.AsciiMode = b.GetOption("ascii_mode")
	state.FullShape = b.GetOption("full_shape")
	return state
}

func (b *nativeBackend) SetOption(name string, value bool) {
	if b.EnsureSession() {
		SetOption(b.sessionID, name, value)
	}
}

func (b *nativeBackend) GetOption(name string) bool {
	if !b.EnsureSession() {
		return false
	}
	return GetOption(b.sessionID, name)
}

func (b *nativeBackend) SelectSchema(schemaID string) bool {
	if !b.EnsureSession() {
		return false
	}
	return SelectSchema(b.sessionID, schemaID)
}

func (b *nativeBackend) CurrentSchema() string {
	if !b.EnsureSession() {
		return ""
	}
	schemaID, ok := GetCurrentSchema(b.sessionID)
	if !ok {
		return ""
	}
	return schemaID
}

func (b *nativeBackend) SyncUserData() bool {
	if !rimeInitOK {
		return false
	}
	return SyncUserData()
}

// Redeploy performs a full RIME redeployment so that on-disk configuration
// changes (such as an updated menu/page_size) invalidate librime's config
// cache and take effect. RimeRedeploy finalizes the service and destroys all
// sessions, so the current session is torn down first and a fresh one is
// created afterwards.
func (b *nativeBackend) Redeploy() bool {
	if !rimeInitOK {
		return false
	}
	b.DestroySession()
	if !RimeRedeploy() {
		log.Println("RIME 重新部署失败")
		return false
	}
	return b.EnsureSession()
}

package fcitx5

import "github.com/EasyIME/pime-go/pime"

type IME struct {
	*pime.TextServiceBase
	composition string
	candidates  []string
}

var haCandidates = []string{"哈", "呵", "喝", "和", "河"}

func New(client *pime.Client) pime.TextService {
	return &IME{TextServiceBase: pime.NewTextServiceBase(client)}
}

func (ime *IME) HandleRequest(req *pime.Request) *pime.Response {
	resp := pime.NewResponse(req.SeqNum, true)
	switch req.Method {
	case "filterKeyDown":
		return ime.filterKeyDown(req, resp)
	case "onKeyDown":
		return ime.onKeyDown(req, resp)
	case "onCompositionTerminated":
		ime.reset()
	}
	return resp
}

func (ime *IME) filterKeyDown(req *pime.Request, resp *pime.Response) *pime.Response {
	charCode := req.CharCode
	if charCode == 0 && req.KeyCode >= 0x41 && req.KeyCode <= 0x5A {
		charCode = req.KeyCode + 32
	}
	if charCode == 'h' {
		ime.composition = "ha"
		ime.candidates = append([]string(nil), haCandidates...)
		resp.CompositionString = ime.composition
		resp.CandidateList = ime.candidates
		resp.ShowCandidates = true
		resp.ReturnValue = 1
		return resp
	}
	resp.ReturnValue = 0
	return resp
}

func (ime *IME) onKeyDown(req *pime.Request, resp *pime.Response) *pime.Response {
	candidates := ime.candidates
	if len(req.CandidateList) > 0 {
		candidates = req.CandidateList
	}
	if req.KeyCode >= 0x31 && req.KeyCode <= 0x39 && len(candidates) > 0 {
		index := req.KeyCode - 0x31
		if index >= 0 && index < len(candidates) {
			resp.CommitString = candidates[index]
			resp.ReturnValue = 1
			resp.ShowCandidates = false
			ime.reset()
			return resp
		}
	}
	return ime.filterKeyDown(req, resp)
}

func (ime *IME) reset() {
	ime.composition = ""
	ime.candidates = nil
}

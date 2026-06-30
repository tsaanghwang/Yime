package simple_pinyin

import "github.com/EasyIME/pime-go/pime"

type IME struct {
	*pime.TextServiceBase
	composition string
	candidates  []string
}

func New(client *pime.Client) pime.TextService {
	return &IME{TextServiceBase: pime.NewTextServiceBase(client)}
}

func (ime *IME) HandleRequest(req *pime.Request) *pime.Response {
	resp := pime.NewResponse(req.SeqNum, true)
	switch req.Method {
	case "filterKeyDown", "onKeyDown":
		return ime.handleKeyDown(req, resp)
	case "onCompositionTerminated":
		ime.reset()
	}
	return resp
}

func (ime *IME) handleKeyDown(req *pime.Request, resp *pime.Response) *pime.Response {
	if req.KeyCode >= 0x31 && req.KeyCode <= 0x39 && len(ime.candidates) > 0 {
		index := req.KeyCode - 0x31
		if index >= 0 && index < len(ime.candidates) {
			resp.CommitString = ime.candidates[index]
			resp.ReturnValue = 1
			resp.ShowCandidates = false
			ime.reset()
			return resp
		}
	}

	if req.KeyCode == 0x0D && len(ime.candidates) > 0 {
		resp.CommitString = ime.candidates[0]
		resp.ReturnValue = 1
		resp.ShowCandidates = false
		ime.reset()
		return resp
	}

	charCode := req.CharCode
	if charCode == 0 && req.KeyCode >= 0x41 && req.KeyCode <= 0x5A {
		charCode = req.KeyCode + 32
	}
	if charCode < 'a' || charCode > 'z' {
		resp.ReturnValue = 0
		return resp
	}

	ime.composition += string(rune(charCode))
	ime.candidates = candidatesFor(ime.composition)

	resp.CompositionString = ime.composition
	resp.CandidateList = ime.candidates
	resp.ShowCandidates = len(ime.candidates) > 0
	resp.ReturnValue = 1
	return resp
}

func (ime *IME) reset() {
	ime.composition = ""
	ime.candidates = nil
}

func candidatesFor(code string) []string {
	switch code {
	case "ni":
		return []string{"测试", "你", "呢"}
	case "nihao":
		return []string{"你好", "你号", "拟好"}
	default:
		if code == "" {
			return nil
		}
		return []string{"测试", "输入", code}
	}
}

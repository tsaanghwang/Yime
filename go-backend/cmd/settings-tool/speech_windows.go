//go:build windows

package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"syscall"
	"unsafe"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/layoutdesigner"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/settings"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/speechruntime"
)

const idSpeechCombo = 120
const idBtnSpeechApply = 205
const wmAppSpeechDone = 0x0400 + 5

func trialSpeechOptions() []settings.ComboOption {
	return []settings.ComboOption{{Label: "关闭", Value: "off"}, {Label: "启用", Value: "on"}}
}

func inspectTrialSpeech(installRoot, stateRoot string, enabled bool) error {
	if !filepath.IsAbs(installRoot) || !filepath.IsAbs(stateRoot) {
		return errors.New("语流设置需要明确的本版安装和状态目录。")
	}
	capability, err := speechruntime.LoadCapability(installRoot)
	if err != nil {
		return err
	}
	if capability == nil {
		return errors.New("当前包未提供已验证的语流模块。")
	}
	product, err := speechruntime.OpenProduct(installRoot, capability.Product.Path, capability.Product.SHA256)
	if err != nil {
		return err
	}
	defer product.Close()
	if !enabled {
		return nil
	}
	indexRoot, dataDir := filepath.Join(installRoot, "indexes"), filepath.Join(installRoot, "data")
	generation, err := layoutdesigner.LoadTrialLayoutGeneration(stateRoot)
	if err == nil {
		indexRoot, dataDir = generation.IndexRoot, generation.DataDir
	} else if !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return product.ValidateIndexes(indexRoot, dataDir)
}

// Keep this explicit write separate from the toolbar's Apply transaction: two
// independently replaceable settings files must not be reported as one commit.
func applyTrialSpeechWithValidation(path string, enabled bool, validate func(bool) error) error {
	if err := validate(enabled); err != nil {
		return err
	}
	return speechruntime.SaveSettings(path, enabled, true)
}

func executeTrialSpeechApply(installRoot, stateRoot string, enabled bool) error {
	return applyTrialSpeechWithValidation(filepath.Join(stateRoot, "speech.json"), enabled,
		func(value bool) error { return inspectTrialSpeech(installRoot, stateRoot, value) })
}

func (state *appState) createSpeechControls() {
	l := state.layout
	createStatic(state.mainHWND, "语流音变", l.speechLabel, 0)
	state.speechHWND = createCombo(state.mainHWND, l.speechCombo, idSpeechCombo)
	for _, option := range trialSpeechOptions() {
		text, _ := syscall.UTF16PtrFromString(option.Label)
		procSendMessageW.Call(uintptr(state.speechHWND), 0x0143, 0, uintptr(unsafe.Pointer(text)))
	}
	state.speechApplyHWND = createButton(state.mainHWND, "应用语流", l.speechApplyButton, idBtnSpeechApply)
	state.speechHintHWND = createStatic(state.mainHWND, "", l.speechHint, 0)
}

type trialSpeechView struct {
	enabled, canApply bool
	hint              string
}

func readTrialSpeechView(stateRoot string, validate func(bool) error) trialSpeechView {
	view := trialSpeechView{hint: "模块或配置不可用；当前包可能尚未提供。"}
	if err := validate(false); err != nil {
		return view
	}
	setting, err := speechruntime.LoadSettings(filepath.Join(stateRoot, "speech.json"))
	if err != nil {
		return view
	}
	view.enabled, view.canApply = setting.Enabled, true
	view.hint = "已准入 24 条上声别名；新输入会话生效。"
	if setting.Enabled {
		if err := validate(true); err != nil {
			view.hint = "已保存启用但资源不匹配，未生效；可关闭。"
		}
	}
	return view
}

func (state *appState) refreshSpeechView() {
	if state.speechHWND == 0 {
		return
	}
	view := readTrialSpeechView(filepath.Dir(state.statePath), func(enabled bool) error {
		return inspectTrialSpeech(state.installRoot, filepath.Dir(state.statePath), enabled)
	})
	value := "off"
	if view.enabled {
		value = "on"
	}
	setComboByValue(state.speechHWND, trialSpeechOptions(), value)
	allow := uintptr(0)
	if view.canApply {
		allow = 1
	}
	moduser32.NewProc("EnableWindow").Call(uintptr(state.speechHWND), allow)
	moduser32.NewProc("EnableWindow").Call(uintptr(state.speechApplyHWND), allow)
	text, _ := syscall.UTF16PtrFromString(view.hint)
	procSetWindowTextW.Call(uintptr(state.speechHintHWND), uintptr(unsafe.Pointer(text)))
}

func (state *appState) startSpeechApply() {
	if !state.experimental || state.speechHWND == 0 {
		return
	}
	if !state.beginOperation("Yime 设置（正在应用语流设置……）") {
		return
	}
	enabled := selectedComboValue(state.speechHWND, trialSpeechOptions()) == "on"
	go func() {
		err := executeTrialSpeechApply(state.installRoot, filepath.Dir(state.statePath), enabled)
		state.applyMu.Lock()
		state.applyErr = err
		state.applyMu.Unlock()
		procPostMessageW.Call(uintptr(state.mainHWND), wmAppSpeechDone, 0, 0)
	}()
}

func (state *appState) completeSpeechApply() error {
	err, _ := state.finishOperation()
	// A rejected target is never left displayed as if it had been saved.
	state.refreshSpeechView()
	return err
}

func (state *appState) finishSpeechApply() {
	err := state.completeSpeechApply()
	if err != nil {
		showError(fmt.Sprintf("语流设置未应用：%v", err))
		return
	}
	showInfo("语流设置已保存。新输入会话生效，当前未提交组合保持不变；必要时重新进入本输入法。")
}

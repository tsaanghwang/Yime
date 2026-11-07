package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/internal/installed18uhost"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
	"github.com/tsaanghwang/Yime/go-backend/internal/tsffrontend"
)

// The installed build refuses the historical portable SendInput entry.
var installedTSFOnly string

const installedTouchHelp = "18u 安装版触控输入\n\n先在目标应用选择独立18u输入法，在正文放好光标，键盘自动跟随可输入的正文。实体键盘在本测试版仅放行 ASCII；中文组码需使用触屏前端。组合和候选显示在键盘内，确认后通过 TSF 写入当前文档。\n三模式、CN/EN、标点、数字和候选操作沿用本包盘面。切模式取消旧组合；英文视图偏好独立保留。\n左右键按 Unicode 字符移动；Home/End 到文档首尾。选区、全选、退格和 Delete 通过 TSF 操作文档。Enter 插入换行，Tab 插入制表符，不移动到下一控件。\n仅 Ctrl+A 支持全选；其他 Ctrl/Alt、功能键及未支持修饰组合明确拒绝，不发送系统快捷键。\n切换正文或输入法会取消旧组合和触点，并自动连接当前正文；最小化、设置或帮助期间暂停，返回后只接受新输入。结果不明时保持停止，请核对正文后点“核对后继续”，旧提交永不补发。\n连接状态变化记录自动保存到当前用户 LocalAppData\\Yime18uTouch\\Diagnostics；设置→最近诊断可查看原因和文件路径，最小化不会删除记录。\n安装版每次启动自动适应当前屏幕可用区域，等比放大并靠底居中；旋转屏幕或工作区变化后重新适应。设置→适应屏幕可随时恢复。此模式是显示缩放，不代表实测毫米尺寸。\n设置→填入实测 mm：输入当前100 mm参考线的实际长度后，切换为本次运行的实测尺寸；参考尺不随显示缩放改变。已认可的实测比例无需再次调整。使用本机实体尺校准；手指、每支笔、不同姿态和应用分别记录。安装及自动回归不代表物理验收通过。"

func prepareInstalledFrontend(o *options, exe string) error {
	if installedTSFOnly != "" && !o.InstalledTSF && !o.Preview && !o.CheckData && !o.CheckPackage {
		if o.Host || o.EnglishOnly || o.Smoke || o.HostSmoke || o.OwnTSFDemo || o.OwnTSFDemoSmoke || o.Shot != "" {
			return fmt.Errorf("安装版不支持旧宿主/演示路线")
		}
		o.InstalledTSF = true
	}
	if !o.InstalledTSF {
		if o.InstallRoot != "" || o.InstallManifestSHA != "" {
			return fmt.Errorf("installation options require --installed-tsf")
		}
		return nil
	}
	if err := tsffrontend.ValidateNativeHost(); err != nil {
		return err
	}
	if o.Host || o.Preview || o.OwnTSFDemo || o.OwnTSFDemoSmoke || o.HostSmoke || o.Smoke || o.CheckData || o.CheckPackage || o.EnglishOnly || o.Shot != "" || o.InputTrace != "" || portableResourcesSHA256 == "" {
		return fmt.Errorf("installed TSF requires a complete dedicated frontend and no alternative execution mode")
	}
	if o.InstallRoot == "" {
		o.InstallRoot = filepath.Dir(filepath.Dir(exe))
	}
	if o.InstallManifestSHA == "" {
		// The simple installer writes its independently inventoried package record
		// under the protected installation root. Do not trust a descriptor's own hash.
		anchor, err := installedFrontendAnchor(o.InstallRoot)
		if err != nil {
			return err
		}
		o.InstallManifestSHA = anchor
	}
	manifest, err := installed18uhost.VerifyInstallation(o.InstallRoot, o.InstallManifestSHA)
	if err != nil {
		return err
	}
	found := false
	for _, file := range manifest.Files {
		if file.Path == "frontend/YimeTouchKeyboard.exe" {
			found = true
		}
	}
	if !found {
		return fmt.Errorf("installed descriptor has no frontend")
	}
	actual, err := os.Stat(exe)
	if err != nil {
		return err
	}
	expected, err := os.Stat(filepath.Join(o.InstallRoot, "frontend", "YimeTouchKeyboard.exe"))
	if err != nil || !os.SameFile(actual, expected) {
		return fmt.Errorf("frontend is not the selected installation payload")
	}
	o.Host = true
	o.TouchUI = true
	return nil
}

func installedFrontendAnchor(root string) (string, error) {
	path := filepath.Join(root, ".setup", "product-package.json")
	raw, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("安装维护清单缺失；请使用完整安装包: %w", err)
	}
	var m struct {
		Format, Product, Target string
		HostArchitecture        string `json:"host_architecture"`
		TSF64Architecture       string `json:"tsf64_architecture"`
		Files                   []struct{ Path, SHA256 string }
	}
	if json.Unmarshal(raw, &m) != nil || m.Format != "yime-simple-package-18u-1" || m.Product != "yimecore-18u" || installed18uhost.PackageTarget == "" || m.Target != installed18uhost.PackageTarget || m.HostArchitecture != strings.TrimPrefix(installed18uhost.PackageTarget, "windows-") || m.TSF64Architecture != installed18uhost.NativeDirectory {
		return "", fmt.Errorf("安装维护清单身份不符")
	}
	anchor := ""
	for _, f := range m.Files {
		if f.Path == installed18uhost.Descriptor {
			if anchor != "" {
				return "", fmt.Errorf("重复的安装清单锚")
			}
			anchor = f.SHA256
		}
	}
	if len(anchor) != 64 {
		return "", fmt.Errorf("安装清单缺少 descriptor SHA-256")
	}
	return anchor, nil
}

// Windows shortcuts are not synthesized on the TSF route. Supported editing
// controls have explicit TSF semantics; Ctrl+A maps to TSF selection only.
func tsfEdit(o tk.Output) (text, key string, extend bool, err error) {
	if o.Alt {
		return "", "", false, fmt.Errorf("TSF 模式不发送 Alt 系统快捷键")
	}
	if o.Ctrl {
		if strings.EqualFold(o.Text, "a") && o.Key == "" && !o.Shift {
			return "", "SelectAll", false, nil
		}
		return "", "", false, fmt.Errorf("TSF 模式仅支持 Ctrl+A 全选；其他快捷键未发送")
	}
	if o.Text != "" && o.Key == "" {
		return o.Text, "", false, nil
	}
	switch o.Key {
	case "ArrowLeft", "ArrowRight", "Home", "End":
		return "", o.Key, o.Shift, nil
	case "Backspace", "Delete", "Enter", "Tab", "SelectAll":
		if !o.Shift {
			return "", o.Key, false, nil
		}
	}
	return "", "", false, fmt.Errorf("此按键或修饰组合没有 TSF 编辑动作；未发送")
}

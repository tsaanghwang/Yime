// yime-layout-designer is an advanced graphical maintenance tool with an
// optional CLI. It invokes layoutdesigner.Apply only after explicit acceptance.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/layoutdesigner"
)

func main() {
	if len(os.Args) < 2 || strings.HasPrefix(os.Args[1], "-") {
		if err := runGraphical(os.Args[1:]); err != nil {
			fmt.Fprintln(os.Stderr, "图形界面启动失败：", err)
			os.Exit(1)
		}
		return
	}
	var err error
	switch os.Args[1] {
	case "show":
		err = show(os.Args[2:])
	case "draft":
		err = draft(os.Args[2:])
	case "validate":
		err = validate(os.Args[2:])
	case "assign":
		err = assign(os.Args[2:])
	case "preview":
		err = preview(os.Args[2:])
	case "apply":
		err = apply(os.Args[2:])
	default:
		usage()
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "错误：", err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Println(`Yime 高级布局维护工具

  show     [-data-dir DIR]
  draft    -output FILE [-data-dir DIR]
  validate -layout FILE
  assign   -layout FILE -id M16 -key t
  preview  -layout FILE [-data-dir DIR]
  apply    -layout FILE [-data-dir DIR] -accept

推荐流程：draft → 多次 assign/手工编辑 → validate → preview → apply -accept`)
}

func dataFlag(fs *flag.FlagSet) *string { return fs.String("data-dir", "", "Yime Rime 数据目录") }
func resolveDataDir(raw string) (string, error) {
	if raw != "" {
		return filepath.Abs(raw)
	}
	cwd, _ := os.Getwd()
	for _, p := range []string{filepath.Join(cwd, "input_methods", "yime", "data"), filepath.Join(cwd, "go-backend", "input_methods", "yime", "data")} {
		if _, err := os.Stat(filepath.Join(p, layoutdesigner.ProfileFileName)); err == nil {
			return p, nil
		}
	}
	exe, _ := os.Executable()
	for _, p := range []string{filepath.Clean(filepath.Join(filepath.Dir(exe), "..", "..", "input_methods", "yime", "data")), filepath.Join(filepath.Dir(exe), "input_methods", "yime", "data")} {
		if _, err := os.Stat(filepath.Join(p, layoutdesigner.ProfileFileName)); err == nil {
			return p, nil
		}
	}
	return "", fmt.Errorf("找不到 %s；请指定 -data-dir", layoutdesigner.ProfileFileName)
}

func show(args []string) error {
	fs := flag.NewFlagSet("show", flag.ContinueOnError)
	data := dataFlag(fs)
	if err := fs.Parse(args); err != nil {
		return err
	}
	dir, err := resolveDataDir(*data)
	if err != nil {
		return err
	}
	p, err := layoutdesigner.LoadProfile(filepath.Join(dir, layoutdesigner.ProfileFileName))
	if err != nil {
		return err
	}
	digest, _ := p.Digest()
	fmt.Printf("%s\nlayout=%s\nalphabet=%s\n\n", p.Name, digest[:12], p.Alphabet())
	ids := layoutdesigner.ExpectedIDs()
	sort.Strings(ids)
	for _, id := range ids {
		fmt.Printf("%-3s  %-2s  %s\n", id, p.Projection[id], layoutdesigner.DescribeID(id))
	}
	return nil
}

func draft(args []string) error {
	fs := flag.NewFlagSet("draft", flag.ContinueOnError)
	data := dataFlag(fs)
	output := fs.String("output", "", "草案 JSON 路径")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *output == "" {
		return fmt.Errorf("必须指定 -output")
	}
	dir, err := resolveDataDir(*data)
	if err != nil {
		return err
	}
	p, err := layoutdesigner.LoadProfile(filepath.Join(dir, layoutdesigner.ProfileFileName))
	if err != nil {
		return err
	}
	p.Name += " draft"
	digest, _ := p.Digest()
	p.BasedOnDigest = digest
	if err := layoutdesigner.WriteProfileAtomic(*output, p); err != nil {
		return err
	}
	fmt.Println("已创建草案：", *output)
	return nil
}

func validate(args []string) error {
	fs := flag.NewFlagSet("validate", flag.ContinueOnError)
	path := fs.String("layout", "", "草案 JSON")
	if err := fs.Parse(args); err != nil {
		return err
	}
	p, err := layoutdesigner.LoadProfile(*path)
	if err != nil {
		return err
	}
	digest, _ := p.Digest()
	fmt.Printf("布局合格：%s，digest=%s\n", p.Name, digest)
	return nil
}

func assign(args []string) error {
	fs := flag.NewFlagSet("assign", flag.ContinueOnError)
	path := fs.String("layout", "", "草案 JSON")
	id := fs.String("id", "", "Yinyuan ID")
	key := fs.String("key", "", "目标键字符")
	if err := fs.Parse(args); err != nil {
		return err
	}
	p, err := layoutdesigner.LoadProfile(*path)
	if err != nil {
		return err
	}
	old := p.Projection[*id]
	occupant := ""
	for other, current := range p.Projection {
		if other != *id && current == *key {
			occupant = other
			break
		}
	}
	if err := p.Assign(*id, *key); err != nil {
		return err
	}
	if err := layoutdesigner.WriteProfileAtomic(*path, p); err != nil {
		return err
	}
	if occupant != "" {
		fmt.Printf("已交换 %s (%s) 与 %s (%s)：%q ↔ %q\n", *id, layoutdesigner.DescribeID(*id), occupant, layoutdesigner.DescribeID(occupant), old, *key)
	} else {
		fmt.Printf("已调整 %s (%s)：%q → %q\n", *id, layoutdesigner.DescribeID(*id), old, *key)
	}
	return nil
}

func preview(args []string) error {
	fs := flag.NewFlagSet("preview", flag.ContinueOnError)
	data := dataFlag(fs)
	path := fs.String("layout", "", "草案 JSON")
	if err := fs.Parse(args); err != nil {
		return err
	}
	dir, err := resolveDataDir(*data)
	if err != nil {
		return err
	}
	p, err := layoutdesigner.LoadProfile(*path)
	if err != nil {
		return err
	}
	plan, err := layoutdesigner.Preview(dir, p)
	if err != nil {
		return err
	}
	return printPlan(plan)
}

func apply(args []string) error {
	fs := flag.NewFlagSet("apply", flag.ContinueOnError)
	data := dataFlag(fs)
	path := fs.String("layout", "", "草案 JSON")
	accept := fs.Bool("accept", false, "确认原子重建全部布局产物")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if !*accept {
		return fmt.Errorf("必须显式指定 -accept；请先运行 preview")
	}
	dir, err := resolveDataDir(*data)
	if err != nil {
		return err
	}
	p, err := layoutdesigner.LoadProfile(*path)
	if err != nil {
		return err
	}
	plan, err := layoutdesigner.Apply(dir, p)
	if err != nil {
		return err
	}
	if err := printPlan(plan); err != nil {
		return err
	}
	fmt.Println("布局及全部派生产物已原子更新；下一步请构建/部署 Yime，启动时会迁移学习记录。")
	return nil
}

func printPlan(plan layoutdesigner.Plan) error {
	data, err := json.MarshalIndent(plan, "", "  ")
	if err != nil {
		return err
	}
	fmt.Println(string(data))
	return nil
}

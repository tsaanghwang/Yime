package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
)

func main() {
	codes := flag.String("codes", "", "path to yime_pinyin_codes.tsv")
	dictionary := flag.String("dictionary", "", "path to canonical full dictionary")
	pronunciations := flag.String("pronunciations", "", "path to source entries.tsv")
	output := flag.String("output", "", "output reverse-source TSV")
	flag.Parse()
	if *codes == "" || *dictionary == "" || *pronunciations == "" || *output == "" {
		flag.Usage()
		os.Exit(2)
	}
	summary, err := reverselookup.DeriveSourceTruth(*codes, *dictionary, *pronunciations, *output)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Printf("Reverse Pinyin source derived: ambiguous_codes=%d affected_entries=%d source_rows=%d\n", summary.AmbiguousFullCodes, summary.AffectedEntries, summary.SourceRows)
}

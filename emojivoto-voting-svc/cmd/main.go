package main

// #cgo LDFLAGS: -Wl,-unresolved-symbols=ignore-in-object-files
import "C"

import (
	"github.com/edgelesssys/coordinator/marble/marble"
)

//export invokemain
func invokemain() { main() }

//export ert_meshentry_premain
func ert_meshentry_premain(argc *C.int, argv ***C.char) {
	if err := marble.PreMain(); err != nil {
		panic(err)
	}

	main()
}

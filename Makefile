# idris2-coverage Makefile

.PHONY: build test clean

build:
	idris2 --build idris2-coverage.ipkg

# Run tests via idris2 executable
test: build
	./build/exec/idris2-cov

# Run actual tests via pack (slower but complete)
test-full:
	pack --cg chez run idris2-coverage.ipkg --exec main src/Coverage/Tests/AllTests.idr

clean:
	rm -rf build

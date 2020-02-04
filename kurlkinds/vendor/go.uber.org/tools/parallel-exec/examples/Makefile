BIN := ../parallel-exec
LIB_SRCS := $(wildcard ../../lib/parallel/*.go)
MAIN_SRCS :=  ../main.go
SRCS := $(LIB_SRCS) $(MAIN_SRCS)

FLAGS ?= --fast-fail

.PHONY: all
all: success one-failure

$(BIN): $(SRCS)
	@echo $(SRCS)
	go build -o $(BIN) $(MAIN_SRCS)

.PHONY: success
success: $(BIN)
	$(BIN) $(FLAGS) config/success.yaml

.PHONY: one-failure
one-failure: $(BIN)
	$(BIN) $(FLAGS) config/one-failure.yaml || true

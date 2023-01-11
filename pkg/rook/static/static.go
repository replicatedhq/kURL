package static

import _ "embed"

//go:embed toolbox.yaml
var Toolbox []byte

//go:embed flex-migrator.yaml
var FlexMigrator []byte

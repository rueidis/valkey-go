module github.com/valkey-io/valkey-go/mock

go 1.21

replace github.com/valkey-io/valkey-go => ../

require (
	github.com/valkey-io/valkey-go v1.0.46
	go.uber.org/mock v0.4.0
)

require golang.org/x/sys v0.24.0 // indirect

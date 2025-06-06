# valkeyaside

A Cache-Aside pattern implementation enhanced by [Client Side Caching](https://redis.io/docs/manual/client-side-caching/).

## Features backed by the Valkey Client Side Caching

Cache-Aside is a widely used pattern to cache other data sources into Valkey. However, there are many issues to be considered when implementing it.

For example, an implementation without locking or versioning may cause a fresh cache to be overridden by a stale one.
And if using a locking mechanism, how to get notified when a lock is released? If using a versioning mechanism, how to version an empty value?

Thankfully, the above issues can be addressed better with the client-side caching along with the following additional benefits: 

* Avoiding unnecessary network round trips. Valkey will proactively invalidate the client-side cache.
* Avoiding Cache Stampede by locking keys with the client-side caching, the same technique used in [valkeylock](https://github.com/valkey-io/valkey-go/tree/main/valkeylock). Only the first cache missed call can update the cache, and others will wait for notifications.

## Example

```go
package main

import (
	"context"
	"database/sql"
	"time"

	"github.com/valkey-io/valkey-go"
	"github.com/valkey-io/valkey-go/valkeyaside"
)

func main() {
	var db sql.DB
	client, err := valkeyaside.NewClient(valkeyaside.ClientOption{
		ClientOption: valkey.ClientOption{InitAddress: []string{"127.0.0.1:6379"}},
	})
	if err != nil {
		panic(err)
	}
	val, err := client.Get(context.Background(), time.Minute, "mykey", func(ctx context.Context, key string) (val string, err error) {
		if err = db.QueryRowContext(ctx, "SELECT val FROM mytab WHERE id = ?", key).Scan(&val); err == sql.ErrNoRows {
			val = "_nil_" // cache nil to avoid penetration.
			err = nil     // clear err in the case of sql.ErrNoRows.
		}
		return
	})
	if err != nil {
		panic(err)
	} else if val == "_nil_" {
		val = ""
		err = sql.ErrNoRows
	} else {
		// ...
	}
}
```

If you want to use cache typed value, not string, you can use `valkeyaside.TypedCacheAsideClient`.

```go
package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"time"

	"github.com/valkey-io/valkey-go"
	"github.com/valkey-io/valkey-go/valkeyaside"
)

type MyValue struct {
	Val string `json:"val"`
}

func main() {
	var db sql.DB
	client, err := valkeyaside.NewClient(valkeyaside.ClientOption{
		ClientOption: valkey.ClientOption{InitAddress: []string{"127.0.0.1:6379"}},
	})
	if err != nil {
		panic(err)
	}

	serializer := func(val *MyValue) (string, error) {
		b, err := json.Marshal(val)
		return string(b), err
	}
	deserializer := func(s string) (*MyValue, error) {
		var val *MyValue
		if err := json.Unmarshal([]byte(s), &val); err != nil {
			return nil, err
		}
		return val, nil
	}

	typedClient := valkeyaside.NewTypedCacheAsideClient(client, serializer, deserializer)
	val, err := typedClient.Get(context.Background(), time.Minute, "myKey", func(ctx context.Context, key string) (*MyValue, error) {
		var val MyValue
		if err := db.QueryRowContext(ctx, "SELECT val FROM mytab WHERE id = ?", key).Scan(&val.Val); err == sql.ErrNoRows {
			return nil, nil
		} else if err != nil {
			return nil, err
		}
		return &val, nil
	})
	// ...
}
```

## Limitation

Currently, requires Valkey >= 7.0.
However, the `UseLuaLock` option is available and allows you to use the `valkeyaside` with older Valkey versions < 7.0 as well.

To configure the Lua fallback option:

```go
client, err := valkeyaside.NewClient(valkeyaside.ClientOption{
    ClientOption: valkey.ClientOption{
        InitAddress: []string{"127.0.0.1:6379"},
    },
    UseLuaLock: true, // Enable Lua script for older Valkey versions
})
if err != nil {
    panic(err)
}
```

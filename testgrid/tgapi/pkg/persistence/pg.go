package persistence

import (
	"database/sql"
	"fmt"
	"os"

	_ "github.com/lib/pq"
)

var DB *sql.DB

func MustGetPGSession() *sql.DB {
	if DB != nil {
		return DB
	}
	db, err := sql.Open("postgres", os.Getenv("DATABASE_URL"))
	if err != nil {
		fmt.Printf("error connecting to postgres: %v\n", err)
		panic(err)
	}

	DB = db
	return db
}

//go:build ignore

package main

import (
	"fmt"
	"log"

	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
)

func main() {
	db, err := gorm.Open(sqlite.Open("./data/agent_hub.db"), &gorm.Config{})
	if err != nil {
		log.Fatal(err)
	}

	// Check service_staffs
	var staffs []map[string]interface{}
	db.Raw("SELECT user_id, nickname, status FROM service_staffs").Scan(&staffs)
	fmt.Println("=== service_staffs ===")
	for _, s := range staffs {
		fmt.Printf("  user_id=%v nickname=%v status=%v\n", s["user_id"], s["nickname"], s["status"])
	}

	// Check recent messages
	var msgs []map[string]interface{}
	db.Raw("SELECT id, client_msg_id, send_id, recv_id, content_type, send_time, status FROM messages ORDER BY id DESC LIMIT 5").Scan(&msgs)
	fmt.Println("\n=== recent messages ===")
	for _, m := range msgs {
		fmt.Printf("  id=%v send=%v recv=%v type=%v status=%v time=%v\n",
			m["id"], m["send_id"], m["recv_id"], m["content_type"], m["status"], m["send_time"])
	}

	// Check conversations
	var convs []map[string]interface{}
	db.Raw("SELECT id, user_a, user_b, last_seq, unread_a, unread_b FROM conversations").Scan(&convs)
	fmt.Println("\n=== conversations ===")
	for _, c := range convs {
		fmt.Printf("  id=%v userA=%v userB=%v lastSeq=%v unreadA=%v unreadB=%v\n",
			c["id"], c["user_a"], c["user_b"], c["last_seq"], c["unread_a"], c["unread_b"])
	}

	// PRAGMA check
	var journalMode string
	db.Raw("PRAGMA journal_mode").Scan(&journalMode)
	fmt.Printf("\njournal_mode=%s\n", journalMode)
}

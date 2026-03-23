package database

import (
	"log"
	"os"

	"im-agent-hub/config"
	"im-agent-hub/model"

	"github.com/glebarez/sqlite"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

// DB is the global database instance.
var DB *gorm.DB

// Init opens the SQLite database, runs migrations, and seeds the default admin.
func Init() {
	if err := os.MkdirAll("./data", 0755); err != nil {
		log.Fatalf("failed to create data directory: %v", err)
	}

	db, err := gorm.Open(sqlite.Open("./data/agent_hub.db"), &gorm.Config{})
	if err != nil {
		log.Fatalf("failed to open database: %v", err)
	}

	if err := db.AutoMigrate(&model.User{}, &model.ServiceStaff{}, &model.Admin{}, &model.Message{}, &model.Conversation{}); err != nil {
		log.Fatalf("failed to auto-migrate: %v", err)
	}

	DB = db

	seedAdmin()
}

// seedAdmin creates the default admin account if none exists.
func seedAdmin() {
	var count int64
	DB.Model(&model.Admin{}).Count(&count)
	if count > 0 {
		return
	}

	hashed, err := bcrypt.GenerateFromPassword([]byte(config.Cfg.Admin.Password), bcrypt.DefaultCost)
	if err != nil {
		log.Fatalf("failed to hash admin password: %v", err)
	}

	admin := model.Admin{
		Username: config.Cfg.Admin.Username,
		Password: string(hashed),
	}
	if err := DB.Create(&admin).Error; err != nil {
		log.Fatalf("failed to create default admin: %v", err)
	}

	log.Println("default admin account created")
}

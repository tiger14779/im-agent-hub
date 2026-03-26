package database

import (
	"fmt"
	"log"

	"im-agent-hub/config"
	"im-agent-hub/model"

	"golang.org/x/crypto/bcrypt"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

// DB is the global database instance.
var DB *gorm.DB

// Init opens the PostgreSQL database, runs migrations, and seeds the default admin.
func Init() {
	cfg := config.Cfg.Database
	dsn := fmt.Sprintf("host=%s port=%d user=%s password=%s dbname=%s sslmode=disable TimeZone=Asia/Shanghai",
		cfg.Host, cfg.Port, cfg.User, cfg.Password, cfg.DBName)

	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		log.Fatalf("failed to open database: %v", err)
	}

	sqlDB, err := db.DB()
	if err != nil {
		log.Fatalf("failed to get underlying sql.DB: %v", err)
	}
	sqlDB.SetMaxOpenConns(20)
	sqlDB.SetMaxIdleConns(5)

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

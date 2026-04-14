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

	if err := db.AutoMigrate(
		&model.User{}, &model.ServiceStaff{}, &model.Admin{},
		&model.Message{}, &model.Conversation{},
		&model.Group{}, &model.GroupMember{},
	); err != nil {
		log.Fatalf("failed to auto-migrate: %v", err)
	}

	// 确保 Content 列为 text 类型（兼容旧迁移可能创建的 varchar(256)）
	db.Exec("ALTER TABLE messages ALTER COLUMN content TYPE text")
	// 确保 last_msg_content 列也为 text 类型
	db.Exec("ALTER TABLE conversations ALTER COLUMN last_msg_content TYPE text")
	// 存量用户 group_nickname 为空的统一填"无昵称"，后续客服逐一手动修改
	db.Exec("UPDATE users SET group_nickname = '无昵称' WHERE group_nickname = '' OR group_nickname IS NULL")

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

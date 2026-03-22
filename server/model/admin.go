package model

type Admin struct {
	ID       uint   `gorm:"primaryKey;autoIncrement"`
	Username string `gorm:"unique"`
	Password string // bcrypt hashed
}

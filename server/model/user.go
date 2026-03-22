package model

import "time"

type User struct {
	ID            string    `gorm:"primaryKey" json:"id"`
	Nickname      string    `json:"nickname"`
	ServiceUserID string    `json:"serviceUserId"`
	Status        int       `json:"status"` // 1=active, 0=disabled
	CreatedAt     time.Time `json:"createdAt"`
	UpdatedAt     time.Time `json:"updatedAt"`
}

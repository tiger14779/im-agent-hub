package model

import "time"

type ServiceStaff struct {
	UserID    string    `gorm:"primaryKey" json:"userId"`
	Nickname  string    `json:"nickname"`
	Avatar    string    `json:"avatar"`
	Status    int       `json:"status"` // 1=active, 0=disabled
	CreatedAt time.Time `json:"createdAt"`
}

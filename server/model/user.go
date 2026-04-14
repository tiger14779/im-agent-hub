package model

import "time"

type User struct {
	ID            string    `gorm:"primaryKey" json:"id"`
	Nickname      string    `json:"nickname"`                  // 备注，PC好友列表/私聊用
	GroupNickname string    `json:"groupNickname"`             // 群内显示名，群消息气泡用，必填
	Avatar        string    `json:"avatar"`                    // 头像 URL
	ServiceUserID string    `json:"serviceUserId"`
	Status        int       `json:"status"` // 1=active, 0=disabled
	CreatedAt     time.Time `json:"createdAt"`
	UpdatedAt     time.Time `json:"updatedAt"`
}

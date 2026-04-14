package model

import "time"

// Group represents a chat group created by a service staff member.
type Group struct {
	ID        string    `gorm:"primaryKey;size:64" json:"id"`
	Name      string    `gorm:"size:128" json:"name"`
	OwnerID   string    `gorm:"index;size:64" json:"ownerId"` // ServiceStaff.UserID
	Dissolved bool      `json:"dissolved"`                    // true after group is disbanded
	CreatedAt time.Time `json:"createdAt"`
}

// GroupMember represents the membership of a user (client or staff) in a group.
type GroupMember struct {
	ID       uint      `gorm:"primaryKey;autoIncrement" json:"id"`
	GroupID  string    `gorm:"uniqueIndex:uidx_group_member;index;size:64" json:"groupId"`
	UserID   string    `gorm:"uniqueIndex:uidx_group_member;size:64" json:"userId"` // User.ID or ServiceStaff.UserID
	Role     string    `gorm:"size:16" json:"role"`                                 // "owner" / "member"
	JoinedAt time.Time `json:"joinedAt"`
}

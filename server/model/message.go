package model

// Message represents a single chat message.
type Message struct {
	ID             uint   `gorm:"primaryKey;autoIncrement" json:"id"`
	ClientMsgID    string `gorm:"uniqueIndex;size:64" json:"clientMsgID"`
	ServerMsgID    string `gorm:"uniqueIndex;size:64" json:"serverMsgID"`
	ConversationID string `gorm:"index;size:128" json:"conversationID"`
	SendID         string `gorm:"index;size:64" json:"sendID"`
	RecvID         string `gorm:"size:64" json:"recvID"`
	ContentType    int    `json:"contentType"`              // 101=text, 102=image, 103=voice, 105=file
	Content        string `gorm:"type:text" json:"content"` // JSON string: {"text":"hello"} or {"url":"...","name":"..."}
	SendTime       int64  `gorm:"index" json:"sendTime"`
	Seq            int64  `gorm:"index" json:"seq"` // per-conversation sequence
	Status         int    `json:"status"`           // 1=sending, 2=delivered, 3=failed
	Deleted        bool   `json:"deleted"`          // soft-delete flag
}

// Conversation tracks the latest state of a chat between two users.
type Conversation struct {
	ID             string `gorm:"primaryKey;size:128" json:"id"`   // "conv_{userA}_{userB}" (sorted)
	UserA          string `gorm:"index;size:64" json:"userA"`      // smaller ID
	UserB          string `gorm:"index;size:64" json:"userB"`      // larger ID
	LastMsgContent string `gorm:"type:text" json:"lastMsgContent"` // preview text
	LastMsgTime    int64  `json:"lastMsgTime"`
	LastSeq        int64  `json:"lastSeq"`
	UnreadA        int    `json:"unreadA"` // unread count for userA
	UnreadB        int    `json:"unreadB"` // unread count for userB
}

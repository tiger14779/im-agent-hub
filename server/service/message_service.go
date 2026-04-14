package service

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"sort"
	"time"

	"im-agent-hub/database"
	"im-agent-hub/model"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// MessageService handles message persistence and retrieval.
type MessageService struct{}

// NewMessageService creates a new MessageService.
func NewMessageService() *MessageService {
	return &MessageService{}
}

// generateServerMsgID produces a unique server-side message ID.
func generateServerMsgID() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		panic("crypto/rand unavailable: " + err.Error())
	}
	return hex.EncodeToString(b)
}

// MakeConversationID builds a deterministic conversation ID from two user IDs.
// The two IDs are sorted so the same pair always produces the same ID.
func MakeConversationID(a, b string) string {
	if a > b {
		a, b = b, a
	}
	return "conv_" + a + "_" + b
}

// sortedPair returns the two user IDs in sorted order.
func sortedPair(a, b string) (string, string) {
	if a > b {
		return b, a
	}
	return a, b
}

// SaveMessage persists a message and updates the conversation.
// It handles deduplication via clientMsgID.
// Returns the saved message (with serverMsgID, seq, sendTime filled) and whether it was a dedup hit.
func (s *MessageService) SaveMessage(sendID, recvID string, contentType int, content, clientMsgID string) (*model.Message, bool, error) {
	// Dedup: if clientMsgID already exists, return the existing message
	if clientMsgID != "" {
		var existing model.Message
		if err := database.DB.Where("client_msg_id = ?", clientMsgID).First(&existing).Error; err == nil {
			log.Printf("[MsgSvc] dedup hit: clientMsgID=%s already exists (seq=%d)", clientMsgID, existing.Seq)
			return &existing, true, nil
		}
	}

	convID := MakeConversationID(sendID, recvID)
	now := time.Now().UnixMilli()
	serverMsgID := generateServerMsgID()

	// Get next seq within a transaction
	msg := &model.Message{
		ClientMsgID:    clientMsgID,
		ServerMsgID:    serverMsgID,
		ConversationID: convID,
		SendID:         sendID,
		RecvID:         recvID,
		ContentType:    contentType,
		Content:        content,
		SendTime:       now,
		Status:         2, // delivered (stored on server)
	}

	err := database.DB.Transaction(func(tx *gorm.DB) error {
		// Ensure conversation exists
		userA, userB := sortedPair(sendID, recvID)
		conv := model.Conversation{ID: convID, UserA: userA, UserB: userB}
		if err := tx.FirstOrCreate(&conv, "id = ?", convID).Error; err != nil {
			return fmt.Errorf("ensure conversation: %w", err)
		}

		// Lock the conversation row (FOR UPDATE) to prevent concurrent seq conflicts
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&conv, "id = ?", convID).Error; err != nil {
			return fmt.Errorf("lock conversation: %w", err)
		}

		nextSeq := conv.LastSeq + 1
		msg.Seq = nextSeq

		// Save the message
		if err := tx.Create(msg).Error; err != nil {
			return fmt.Errorf("save message: %w", err)
		}

		// Build preview text
		preview := contentPreview(contentType, content)

		// Update conversation: increment unread for receiver
		updates := map[string]interface{}{
			"last_msg_content": preview,
			"last_msg_time":    now,
			"last_seq":         nextSeq,
		}
		// Increment unread for the OTHER user
		if recvID == userA {
			updates["unread_a"] = gorm.Expr("unread_a + 1")
		} else {
			updates["unread_b"] = gorm.Expr("unread_b + 1")
		}
		if err := tx.Model(&model.Conversation{}).Where("id = ?", convID).Updates(updates).Error; err != nil {
			return fmt.Errorf("update conversation: %w", err)
		}

		return nil
	})

	if err != nil {
		return nil, false, err
	}

	return msg, false, nil
}

// contentPreview generates a short preview string for the conversation list.
func contentPreview(contentType int, content string) string {
	switch contentType {
	case 101: // text
		var obj map[string]interface{}
		if err := json.Unmarshal([]byte(content), &obj); err == nil {
			if text, ok := obj["text"].(string); ok {
				runes := []rune(text)
				if len(runes) > 50 {
					return string(runes[:50]) + "..."
				}
				return text
			}
		}
		return "[文本]"
	case 102:
		return "[图片]"
	case 103:
		return "[语音]"
	case 105:
		return "[文件]"
	default:
		return "[消息]"
	}
}

// GetHistory returns messages for a conversation, ordered by seq ascending.
// If beforeSeq > 0, returns messages with seq < beforeSeq (for pagination).
// Returns at most `limit` messages.
func (s *MessageService) GetHistory(convID string, beforeSeq int64, limit int) ([]model.Message, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}

	var msgs []model.Message
	q := database.DB.Where("conversation_id = ? AND deleted = ?", convID, false)
	if beforeSeq > 0 {
		q = q.Where("seq < ?", beforeSeq)
	}
	if err := q.Order("seq desc").Limit(limit).Find(&msgs).Error; err != nil {
		return nil, err
	}

	// Reverse to ascending order
	sort.Slice(msgs, func(i, j int) bool {
		return msgs[i].Seq < msgs[j].Seq
	})

	return msgs, nil
}

// GetNewMessages returns messages with seq > afterSeq for a conversation.
func (s *MessageService) GetNewMessages(convID string, afterSeq int64) ([]model.Message, error) {
	var msgs []model.Message
	err := database.DB.Where("conversation_id = ? AND seq > ?", convID, afterSeq).
		Order("seq asc").Limit(100).Find(&msgs).Error
	return msgs, err
}

// MarkRead clears the unread counter for a user in a conversation.
func (s *MessageService) MarkRead(convID, userID string) error {
	var conv model.Conversation
	if err := database.DB.First(&conv, "id = ?", convID).Error; err != nil {
		return err
	}

	if userID == conv.UserA {
		return database.DB.Model(&conv).Update("unread_a", 0).Error
	}
	return database.DB.Model(&conv).Update("unread_b", 0).Error
}

// GetConversationsForUser returns all conversations involving the given user.
func (s *MessageService) GetConversationsForUser(userID string) ([]model.Conversation, error) {
	var convs []model.Conversation
	err := database.DB.Where("user_a = ? OR user_b = ?", userID, userID).
		Order("last_msg_time desc").Find(&convs).Error
	return convs, err
}

// GetUnreadCount returns the unread message count for a user in a conversation.
func (s *MessageService) GetUnreadCount(convID, userID string) int {
	var conv model.Conversation
	if err := database.DB.First(&conv, "id = ?", convID).Error; err != nil {
		return 0
	}
	if userID == conv.UserA {
		return conv.UnreadA
	}
	return conv.UnreadB
}

// DeleteMessage soft-deletes a message by serverMsgID.
// Returns the message (for routing the notification) and error.
func (s *MessageService) DeleteMessage(serverMsgID string) (*model.Message, error) {
	var msg model.Message
	if err := database.DB.Where("server_msg_id = ?", serverMsgID).First(&msg).Error; err != nil {
		return nil, fmt.Errorf("message not found: %w", err)
	}
	if err := database.DB.Model(&msg).Update("deleted", true).Error; err != nil {
		return nil, fmt.Errorf("delete message: %w", err)
	}
	return &msg, nil
}

// CleanupOldMessages deletes messages and files older than the given cutoff.
func (s *MessageService) CleanupOldMessages(retentionDays int) (int64, error) {
	cutoff := time.Now().AddDate(0, 0, -retentionDays).UnixMilli()
	result := database.DB.Where("send_time < ?", cutoff).Delete(&model.Message{})
	if result.Error != nil {
		return 0, result.Error
	}
	log.Printf("[Cleanup] deleted %d messages older than %d days", result.RowsAffected, retentionDays)
	return result.RowsAffected, nil
}

// SaveGroupMessage persists a group message.
// ConversationID = "group_" + groupID; FOR UPDATE lock ensures monotone seq.
// Returns the saved message, isDup bool, and error.
func (s *MessageService) SaveGroupMessage(sendID, groupID string, contentType int, content, clientMsgID, senderName string) (*model.Message, bool, error) {
	// Dedup
	if clientMsgID != "" {
		var existing model.Message
		if err := database.DB.Where("client_msg_id = ?", clientMsgID).First(&existing).Error; err == nil {
			log.Printf("[MsgSvc] group dedup hit: clientMsgID=%s (seq=%d)", clientMsgID, existing.Seq)
			return &existing, true, nil
		}
	}

	convID := "group_" + groupID
	now := time.Now().UnixMilli()
	serverMsgID := generateServerMsgID()

	msg := &model.Message{
		ClientMsgID:    clientMsgID,
		ServerMsgID:    serverMsgID,
		ConversationID: convID,
		SendID:         sendID,
		RecvID:         groupID,
		ContentType:    contentType,
		Content:        content,
		SendTime:       now,
		Status:         2,
		IsGroup:        true,
		SenderName:     senderName,
	}

	err := database.DB.Transaction(func(tx *gorm.DB) error {
		// Ensure group conversation row exists
		conv := model.Conversation{
			ID:      convID,
			GroupID: groupID,
		}
		if err := tx.FirstOrCreate(&conv, "id = ?", convID).Error; err != nil {
			return fmt.Errorf("ensure group conversation: %w", err)
		}

		// Lock the conversation row for seq assignment
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&conv, "id = ?", convID).Error; err != nil {
			return fmt.Errorf("lock group conversation: %w", err)
		}

		nextSeq := conv.LastSeq + 1
		msg.Seq = nextSeq

		if err := tx.Create(msg).Error; err != nil {
			return fmt.Errorf("save group message: %w", err)
		}

		preview := contentPreview(contentType, content)
		if err := tx.Model(&model.Conversation{}).Where("id = ?", convID).Updates(map[string]interface{}{
			"last_msg_content": preview,
			"last_msg_time":    now,
			"last_seq":         nextSeq,
		}).Error; err != nil {
			return fmt.Errorf("update group conversation: %w", err)
		}
		return nil
	})

	if err != nil {
		return nil, false, err
	}
	return msg, false, nil
}

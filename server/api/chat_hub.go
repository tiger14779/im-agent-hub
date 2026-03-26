package api

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"

	"im-agent-hub/database"
	"im-agent-hub/model"
	"im-agent-hub/service"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

var wsUpgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

// ChatHub manages all WebSocket connections and message routing.
type ChatHub struct {
	clients map[string]*ChatConn // userID -> connection
	mu      sync.RWMutex
	msgSvc  *service.MessageService
}

// ChatConn represents a single WebSocket connection.
type ChatConn struct {
	conn   *websocket.Conn
	userID string
	role   string // "client" or "staff"
	stopCh chan struct{}
	mu     sync.Mutex // protects conn writes
}

// NewChatHub creates a new ChatHub.
func NewChatHub(msgSvc *service.MessageService) *ChatHub {
	return &ChatHub{
		clients: make(map[string]*ChatConn),
		msgSvc:  msgSvc,
	}
}

// WsEnvelope is the JSON envelope for all WebSocket messages.
type WsEnvelope struct {
	Type string          `json:"type"`
	Data json.RawMessage `json:"data"`
}

// HandleClientWS handles WebSocket for H5 client users.
// GET /api/ws?userId=xxx&token=xxx
func (h *ChatHub) HandleClientWS(c *gin.Context) {
	userID := c.Query("userId")
	token := c.Query("token")
	if userID == "" || token == "" {
		c.JSON(401, gin.H{"error": "missing userId or token"})
		return
	}

	// Verify user exists and is active
	var user model.User
	if err := database.DB.First(&user, "id = ? AND status = 1", userID).Error; err != nil {
		c.JSON(401, gin.H{"error": "invalid user"})
		return
	}

	// TODO: verify JWT token properly if needed

	h.upgradeAndServe(c, userID, "client")
}

// HandleStaffWS handles WebSocket for PC service staff.
// GET /api/service/ws?staffId=xxx&token=xxx
func (h *ChatHub) HandleStaffWS(c *gin.Context) {
	staffID := c.Query("staffId")
	token := c.Query("token")
	log.Printf("[WS] HandleStaffWS called: staffId=%s tokenLen=%d", staffID, len(token))
	if staffID == "" || token == "" {
		log.Printf("[WS] HandleStaffWS rejected: missing staffId or token")
		c.JSON(401, gin.H{"error": "missing staffId or token"})
		return
	}

	// Verify staff exists
	var staff model.ServiceStaff
	if err := database.DB.First(&staff, "user_id = ? AND status = 1", staffID).Error; err != nil {
		log.Printf("[WS] HandleStaffWS rejected: staff %s not found: %v", staffID, err)
		c.JSON(401, gin.H{"error": "invalid staff"})
		return
	}

	log.Printf("[WS] HandleStaffWS: upgrading connection for %s", staffID)
	h.upgradeAndServe(c, staffID, "staff")
}

func (h *ChatHub) upgradeAndServe(c *gin.Context, userID, role string) {
	conn, err := wsUpgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Printf("[WS] upgrade error for %s: %v", userID, err)
		return
	}

	cc := &ChatConn{
		conn:   conn,
		userID: userID,
		role:   role,
		stopCh: make(chan struct{}),
	}

	// Replace existing connection for this user
	h.mu.Lock()
	if old, ok := h.clients[userID]; ok {
		close(old.stopCh)
		old.conn.Close()
	}
	h.clients[userID] = cc
	h.mu.Unlock()

	log.Printf("[WS] %s (%s) connected", userID, role)

	// Read loop
	h.readLoop(cc)

	// Cleanup
	h.mu.Lock()
	if h.clients[userID] == cc {
		delete(h.clients, userID)
	}
	h.mu.Unlock()

	select {
	case <-cc.stopCh:
	default:
		close(cc.stopCh)
	}
	conn.Close()
	log.Printf("[WS] %s disconnected", userID)
}

func (h *ChatHub) readLoop(cc *ChatConn) {
	for {
		_, raw, err := cc.conn.ReadMessage()
		if err != nil {
			break
		}

		var env WsEnvelope
		if err := json.Unmarshal(raw, &env); err != nil {
			continue
		}

		switch env.Type {
		case "send_message":
			h.handleSendMessage(cc, env.Data)
		case "load_history":
			h.handleLoadHistory(cc, env.Data)
		case "mark_read":
			h.handleMarkRead(cc, env.Data)
		case "ping":
			h.sendJSON(cc, map[string]interface{}{"type": "pong"})
		}
	}
}

// handleSendMessage processes a message from any connected user.
func (h *ChatHub) handleSendMessage(cc *ChatConn, data json.RawMessage) {
	var req struct {
		RecvID      string          `json:"recvId"`
		ContentType int             `json:"contentType"`
		Content     json.RawMessage `json:"content"` // string or object
		ClientMsgID string          `json:"clientMsgId"`
	}
	if err := json.Unmarshal(data, &req); err != nil {
		log.Printf("[WS] bad send_message from %s: %v", cc.userID, err)
		return
	}

	// Normalize content to a JSON string for storage.
	// H5 sends a JSON string: "{ ... }", PC sends a JSON object: { ... }
	contentStr := string(req.Content)
	if len(contentStr) > 0 && contentStr[0] == '"' {
		// It's a JSON-encoded string — unwrap it
		var s string
		if err := json.Unmarshal(req.Content, &s); err == nil {
			contentStr = s
		}
	}

	log.Printf("[WS] send_message from=%s to=%s type=%d", cc.userID, req.RecvID, req.ContentType)

	// Save to database
	msg, err := h.msgSvc.SaveMessage(cc.userID, req.RecvID, req.ContentType, contentStr, req.ClientMsgID)
	if err != nil {
		log.Printf("[WS] save message error: %v", err)
		// 发送失败 ACK 给发送者（查找当前最新连接）
		h.sendToUser(cc.userID, map[string]interface{}{
			"type": "message_ack",
			"data": map[string]interface{}{
				"clientMsgId": req.ClientMsgID,
				"status":      3,
				"error":       err.Error(),
			},
		})
		return
	}

	// ACK back to sender（查找当前最新连接，防止重连后旧连接已关闭）
	h.sendToUser(cc.userID, map[string]interface{}{
		"type": "message_ack",
		"data": map[string]interface{}{
			"clientMsgId": req.ClientMsgID,
			"serverMsgId": msg.ServerMsgID,
			"seq":         msg.Seq,
			"sendTime":    msg.SendTime,
			"status":      2,
		},
	})

	// Push to receiver if online
	h.sendToUser(req.RecvID, map[string]interface{}{
		"type": "new_message",
		"data": map[string]interface{}{
			"serverMsgID":    msg.ServerMsgID,
			"clientMsgID":    msg.ClientMsgID,
			"sendID":         msg.SendID,
			"recvID":         msg.RecvID,
			"conversationID": msg.ConversationID,
			"contentType":    msg.ContentType,
			"content":        msg.Content,
			"sendTime":       msg.SendTime,
			"seq":            msg.Seq,
			"status":         msg.Status,
		},
	})
}

// handleLoadHistory returns message history for a conversation.
func (h *ChatHub) handleLoadHistory(cc *ChatConn, data json.RawMessage) {
	var req struct {
		PeerUserID string `json:"peerUserId"`
		BeforeSeq  int64  `json:"beforeSeq"` // 0 = latest
		Limit      int    `json:"limit"`     // default 50
	}
	if err := json.Unmarshal(data, &req); err != nil {
		return
	}

	convID := service.MakeConversationID(cc.userID, req.PeerUserID)
	msgs, err := h.msgSvc.GetHistory(convID, req.BeforeSeq, req.Limit)

	resp := map[string]interface{}{
		"type": "history",
		"data": map[string]interface{}{
			"peerUserId":     req.PeerUserID,
			"conversationId": convID,
			"messages":       msgs,
			"hasMore":        len(msgs) >= req.Limit || (req.Limit == 0 && len(msgs) >= 50),
		},
	}
	if err != nil {
		log.Printf("[WS] load_history error: %v", err)
		resp["data"] = map[string]interface{}{
			"peerUserId": req.PeerUserID,
			"messages":   []interface{}{},
			"hasMore":    false,
		}
	}

	// Mark as read while loading history
	_ = h.msgSvc.MarkRead(convID, cc.userID)

	h.sendJSON(cc, resp)
}

// handleMarkRead clears unread count for a conversation.
func (h *ChatHub) handleMarkRead(cc *ChatConn, data json.RawMessage) {
	var req struct {
		PeerUserID string `json:"peerUserId"`
	}
	if err := json.Unmarshal(data, &req); err != nil {
		return
	}
	convID := service.MakeConversationID(cc.userID, req.PeerUserID)
	_ = h.msgSvc.MarkRead(convID, cc.userID)
}

// sendJSON sends a JSON message to a client, protected by mutex.
func (h *ChatHub) sendJSON(cc *ChatConn, v interface{}) {
	cc.mu.Lock()
	defer cc.mu.Unlock()
	if err := cc.conn.WriteJSON(v); err != nil {
		log.Printf("[WS] write error to %s: %v", cc.userID, err)
	}
}

// sendToUser looks up the CURRENT connection for userID and sends.
// This is safe even if the user has reconnected (uses latest connection).
func (h *ChatHub) sendToUser(userID string, v interface{}) {
	h.mu.RLock()
	conn, ok := h.clients[userID]
	h.mu.RUnlock()
	if ok {
		h.sendJSON(conn, v)
	}
}

// NotifyContactsUpdated sends a contacts_updated push to a staff member so their client refreshes.
func (h *ChatHub) NotifyContactsUpdated(staffID string) {
	h.mu.RLock()
	cc, ok := h.clients[staffID]
	h.mu.RUnlock()
	if ok {
		h.sendJSON(cc, map[string]interface{}{
			"type": "contacts_updated",
			"data": map[string]interface{}{},
		})
		log.Printf("[WS] contacts_updated pushed to %s", staffID)
	}
}

// IsOnline returns true if the user has an active WebSocket connection.
func (h *ChatHub) IsOnline(userID string) bool {
	h.mu.RLock()
	defer h.mu.RUnlock()
	_, ok := h.clients[userID]
	return ok
}

// OnlineCount returns the total number of connected users.
func (h *ChatHub) OnlineCount() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.clients)
}

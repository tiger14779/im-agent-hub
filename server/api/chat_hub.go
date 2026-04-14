package api

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"

	"im-agent-hub/database"
	"im-agent-hub/model"
	"im-agent-hub/service"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

var wsUpgrader = websocket.Upgrader{
	CheckOrigin:     func(r *http.Request) bool { return true },
	ReadBufferSize:  65536,
	WriteBufferSize: 65536,
}

const (
	writeWait  = 10 * time.Second // max time to write a message
	pongWait   = 30 * time.Second // max time between pongs from client
	pingPeriod = 20 * time.Second // must be < pongWait
)

// ChatHub manages all WebSocket connections and message routing.
type ChatHub struct {
	clients map[string]*ChatConn // userID -> connection
	mu      sync.RWMutex
	msgSvc  *service.MessageService
	msgCh   chan msgTask // serialized message-write channel
}

// msgTask is a send_message job queued for sequential DB processing.
type msgTask struct {
	cc      *ChatConn
	data    json.RawMessage
	isGroup bool
}

// ChatConn represents a single WebSocket connection.
// Each connection has a dedicated write channel + goroutine for serialized writes.
type ChatConn struct {
	conn       *websocket.Conn
	userID     string
	role       string // "client" or "staff"
	visibility string // "visible" or "hidden" (H5 page visibility)
	stopCh     chan struct{}
	sendCh     chan []byte // buffered outgoing message channel
}

// NewChatHub creates a new ChatHub.
func NewChatHub(msgSvc *service.MessageService) *ChatHub {
	h := &ChatHub{
		clients: make(map[string]*ChatConn),
		msgSvc:  msgSvc,
		msgCh:   make(chan msgTask, 256), // buffered channel
	}
	// Start worker pool for message writes (PostgreSQL supports full concurrency)
	for i := 0; i < 20; i++ {
		go h.msgWorker()
	}
	return h
}

// msgWorker processes send_message tasks sequentially from the channel.
func (h *ChatHub) msgWorker() {
	for task := range h.msgCh {
		if task.isGroup {
			h.handleSendGroupMessage(task.cc, task.data)
		} else {
			h.handleSendMessage(task.cc, task.data)
		}
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

	// Set read deadline; pong handler resets it.
	conn.SetReadDeadline(time.Now().Add(pongWait))
	conn.SetPongHandler(func(string) error {
		conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})
	// 取消默认 32KB 读取限制，允许大消息（默认 32768 会导致长文本断连）
	conn.SetReadLimit(0)

	cc := &ChatConn{
		conn:       conn,
		userID:     userID,
		role:       role,
		visibility: "visible",
		stopCh:     make(chan struct{}),
		sendCh:     make(chan []byte, 128), // buffered: avoids blocking senders
	}

	// Replace existing connection for this user
	h.mu.Lock()
	if old, ok := h.clients[userID]; ok {
		close(old.stopCh)
		old.conn.Close()
		// Drain any queued messages from old sendCh into the new connection,
		// preventing message loss during reconnection.
		go func(oldCh, newCh chan []byte) {
			for {
				select {
				case msg, ok := <-oldCh:
					if !ok {
						return
					}
					select {
					case newCh <- msg:
						log.Printf("[WS] drained 1 message from old sendCh to new for %s", userID)
					default:
						log.Printf("[WS] new sendCh full while draining for %s, message dropped", userID)
					}
				default:
					return // no more queued messages
				}
			}
		}(old.sendCh, cc.sendCh)
	}
	h.clients[userID] = cc
	h.mu.Unlock()

	log.Printf("[WS] %s (%s) connected", userID, role)

	// Notify staff clients when an H5 client comes online
	if role == "client" {
		h.broadcastClientStatus(userID, "online")
	}

	// Dedicated write goroutine: serialized writes + ping keepalive
	go h.writeLoop(cc)

	// Read loop
	h.readLoop(cc)

	// Cleanup
	removedCurrent := false
	h.mu.Lock()
	if h.clients[userID] == cc {
		delete(h.clients, userID)
		removedCurrent = true
		log.Printf("[WS] %s (%s) removed from clients map", userID, role)
	} else {
		log.Printf("[WS] %s (%s) cleanup skipped (replaced by newer connection)", userID, role)
	}
	h.mu.Unlock()

	// Notify staff clients when an H5 client goes offline.
	// If this connection has been replaced by a newer one, skip offline broadcast.
	if role == "client" && removedCurrent {
		h.broadcastClientStatus(userID, "offline")
	}

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
			log.Printf("[WS] readLoop error for %s: %v", cc.userID, err)
			break
		}

		var env WsEnvelope
		if err := json.Unmarshal(raw, &env); err != nil {
			log.Printf("[WS] envelope parse error from %s (len=%d): %v", cc.userID, len(raw), err)
			continue
		}

		switch env.Type {
		case "send_message":
			select {
			case h.msgCh <- msgTask{cc: cc, data: env.Data}:
			default:
				log.Printf("[WS] message channel full, dropping message from %s", cc.userID)
				// 队列满时也要返回失败 ACK，否则客户端只能等超时
				var partial struct {
					ClientMsgID string `json:"clientMsgId"`
				}
				_ = json.Unmarshal(env.Data, &partial)
				if partial.ClientMsgID != "" {
					h.sendJSON(cc, map[string]interface{}{
						"type": "message_ack",
						"data": map[string]interface{}{
							"clientMsgId": partial.ClientMsgID,
							"status":      3,
							"error":       "server busy",
						},
					})
				}
			}
		case "send_group_message":
			select {
			case h.msgCh <- msgTask{cc: cc, data: env.Data, isGroup: true}:
			default:
				log.Printf("[WS] group message channel full, dropping message from %s", cc.userID)
				var partial struct {
					ClientMsgID string `json:"clientMsgId"`
				}
				_ = json.Unmarshal(env.Data, &partial)
				if partial.ClientMsgID != "" {
					h.sendJSON(cc, map[string]interface{}{
						"type": "message_ack",
						"data": map[string]interface{}{
							"clientMsgId": partial.ClientMsgID,
							"status":      3,
							"error":       "server busy",
						},
					})
				}
			}
		case "load_history":
			h.handleLoadHistory(cc, env.Data)
		case "mark_read":
			h.handleMarkRead(cc, env.Data)
		case "delete_message":
			h.handleDeleteMessage(cc, env.Data)
		case "ping":
			cc.conn.SetReadDeadline(time.Now().Add(pongWait))
			h.sendJSON(cc, map[string]interface{}{"type": "pong"})
		case "visibility":
			h.handleVisibility(cc, env.Data)
		case "query_online":
			h.handleQueryOnline(cc)
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
		// 解析失败也要返回 ACK，否则客户端会等到超时
		var partial struct {
			ClientMsgID string `json:"clientMsgId"`
		}
		_ = json.Unmarshal(data, &partial)
		if partial.ClientMsgID != "" {
			h.sendToUser(cc.userID, map[string]interface{}{
				"type": "message_ack",
				"data": map[string]interface{}{
					"clientMsgId": partial.ClientMsgID,
					"status":      3,
					"error":       "invalid message format",
				},
			})
		}
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

	log.Printf("[WS] send_message from=%s to=%s type=%d contentLen=%d", cc.userID, req.RecvID, req.ContentType, len(contentStr))

	// Save to database
	msg, isDup, err := h.msgSvc.SaveMessage(cc.userID, req.RecvID, req.ContentType, contentStr, req.ClientMsgID)
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

	// 去重命中：只发ACK不推送，避免接收方收到重复消息
	if isDup {
		log.Printf("[WS] dedup: skipping push to %s for clientMsgID=%s", req.RecvID, req.ClientMsgID)
		return
	}

	// Push to receiver if online
	log.Printf("[WS] routing new_message from=%s to=%s seq=%d", cc.userID, req.RecvID, msg.Seq)
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

// handleDeleteMessage soft-deletes a message and notifies the peer.
func (h *ChatHub) handleDeleteMessage(cc *ChatConn, data json.RawMessage) {
	var req struct {
		ServerMsgID string `json:"serverMsgId"`
	}
	if err := json.Unmarshal(data, &req); err != nil {
		return
	}
	if req.ServerMsgID == "" {
		return
	}

	// 仅允许客服端（PC）删除消息
	if cc.role != "staff" {
		log.Printf("[WS] delete_message rejected: user %s is not staff (role=%s)", cc.userID, cc.role)
		return
	}

	msg, err := h.msgSvc.DeleteMessage(req.ServerMsgID)
	if err != nil {
		log.Printf("[WS] delete_message error from %s: %v", cc.userID, err)
		return
	}

	log.Printf("[WS] delete_message: %s deleted serverMsgID=%s", cc.userID, req.ServerMsgID)

	// ACK back to sender
	h.sendToUser(cc.userID, map[string]interface{}{
		"type": "delete_ack",
		"data": map[string]interface{}{
			"serverMsgId": req.ServerMsgID,
		},
	})

	// Notify the peer
	peerID := msg.RecvID
	if peerID == cc.userID {
		peerID = msg.SendID
	}
	h.sendToUser(peerID, map[string]interface{}{
		"type": "message_deleted",
		"data": map[string]interface{}{
			"serverMsgId": req.ServerMsgID,
		},
	})
}

// sendJSON marshals v to JSON and queues it on the connection's write channel.
// Non-blocking: if the channel is full or connection is closed, the message is dropped.
func (h *ChatHub) sendJSON(cc *ChatConn, v interface{}) {
	data, err := json.Marshal(v)
	if err != nil {
		log.Printf("[WS] marshal error for %s: %v", cc.userID, err)
		return
	}
	select {
	case cc.sendCh <- data:
	case <-cc.stopCh:
		log.Printf("[WS] connection stopped, dropping message for %s", cc.userID)
	default:
		log.Printf("[WS] send channel full, dropping message for %s", cc.userID)
	}
}

// writeLoop is the single goroutine that writes to the WebSocket.
// It handles both queued JSON messages and periodic ping keepalives.
// This eliminates concurrent write contention entirely.
func (h *ChatHub) writeLoop(cc *ChatConn) {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		// writeLoop 退出后必须关闭连接，否则 readLoop 还在跑，
		// sendCh 无人消费，新消息会被静默丢弃
		cc.conn.Close()
		log.Printf("[WS] writeLoop exited for %s, connection closed", cc.userID)
	}()
	for {
		select {
		case msg, ok := <-cc.sendCh:
			if !ok {
				return // channel closed
			}
			cc.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := cc.conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				log.Printf("[WS] write error to %s: %v", cc.userID, err)
				return
			}
		case <-ticker.C:
			cc.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := cc.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				log.Printf("[WS] ping write error to %s: %v", cc.userID, err)
				return
			}
		case <-cc.stopCh:
			return
		}
	}
}

// sendToUser looks up the CURRENT connection for userID and sends.
// This is safe even if the user has reconnected (uses latest connection).
func (h *ChatHub) sendToUser(userID string, v interface{}) {
	h.mu.RLock()
	conn, ok := h.clients[userID]
	var totalClients int
	if !ok {
		totalClients = len(h.clients)
	}
	h.mu.RUnlock()
	if ok {
		log.Printf("[WS] sendToUser: found connection for %s (role=%s), sending", userID, conn.role)
		h.sendJSON(conn, v)
	} else {
		log.Printf("[WS] sendToUser: user %s NOT FOUND in clients map (total=%d)", userID, totalClients)
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

// broadcastClientStatus sends client_online_status to all connected staff members.
func (h *ChatHub) broadcastClientStatus(clientUserID, status string) {
	msg := map[string]interface{}{
		"type": "client_online_status",
		"data": map[string]interface{}{
			"userId": clientUserID,
			"status": status, // "online", "background", "offline"
		},
	}
	h.mu.RLock()
	var staffConns []*ChatConn
	for _, cc := range h.clients {
		if cc.role == "staff" {
			staffConns = append(staffConns, cc)
		}
	}
	h.mu.RUnlock()

	for _, cc := range staffConns {
		h.sendJSON(cc, msg)
	}
	log.Printf("[WS] broadcast client_online_status: userId=%s status=%s to %d staff", clientUserID, status, len(staffConns))
}

// broadcastGroupEvent sends a group event to all online members of a group.
func (h *ChatHub) broadcastGroupEvent(groupID, eventType string, payload map[string]interface{}) {
	var members []model.GroupMember
	database.DB.Where("group_id = ?", groupID).Find(&members)

	for _, m := range members {
		memberID := m.UserID
		h.sendToUser(memberID, map[string]interface{}{
			"type": eventType,
			"data": payload,
		})
	}
	log.Printf("[WS] broadcastGroupEvent: groupId=%s event=%s to %d members", groupID, eventType, len(members))
}

// handleSendGroupMessage processes a group message from any connected user.
// Concurrent fan-out: saves once with FOR UPDATE seq lock, then pushes to all members in parallel.
func (h *ChatHub) handleSendGroupMessage(cc *ChatConn, data json.RawMessage) {
	var req struct {
		GroupID     string          `json:"groupId"`
		ContentType int             `json:"contentType"`
		Content     json.RawMessage `json:"content"`
		ClientMsgID string          `json:"clientMsgId"`
	}
	if err := json.Unmarshal(data, &req); err != nil || req.GroupID == "" {
		log.Printf("[WS] bad send_group_message from %s", cc.userID)
		var partial struct {
			ClientMsgID string `json:"clientMsgId"`
		}
		_ = json.Unmarshal(data, &partial)
		if partial.ClientMsgID != "" {
			h.sendToUser(cc.userID, map[string]interface{}{
				"type": "message_ack",
				"data": map[string]interface{}{"clientMsgId": partial.ClientMsgID, "status": 3, "error": "invalid group message"},
			})
		}
		return
	}

	// Verify group exists and not dissolved
	var g model.Group
	if err := database.DB.First(&g, "id = ? AND dissolved = false", req.GroupID).Error; err != nil {
		h.sendToUser(cc.userID, map[string]interface{}{
			"type": "message_ack",
			"data": map[string]interface{}{"clientMsgId": req.ClientMsgID, "status": 3, "error": "group not found or dissolved"},
		})
		return
	}

	// Verify sender is a group member
	var membership model.GroupMember
	if err := database.DB.First(&membership, "group_id = ? AND user_id = ?", req.GroupID, cc.userID).Error; err != nil {
		h.sendToUser(cc.userID, map[string]interface{}{
			"type": "message_ack",
			"data": map[string]interface{}{"clientMsgId": req.ClientMsgID, "status": 3, "error": "not a group member"},
		})
		return
	}

	// Normalize content
	contentStr := string(req.Content)
	if len(contentStr) > 0 && contentStr[0] == '"' {
		var s string
		if err := json.Unmarshal(req.Content, &s); err == nil {
			contentStr = s
		}
	}

	// Determine sender display name (fixed at send time)
	senderName := ""
	var u model.User
	if err := database.DB.First(&u, "id = ?", cc.userID).Error; err == nil {
		senderName = u.GroupNickname
	} else {
		// sender is staff
		var s model.ServiceStaff
		if err2 := database.DB.First(&s, "user_id = ?", cc.userID).Error; err2 == nil {
			senderName = s.Nickname
		}
	}

	// Save group message — RecvID = groupID, IsGroup = true, SenderName fixed
	msg, isDup, err := h.msgSvc.SaveGroupMessage(cc.userID, req.GroupID, req.ContentType, contentStr, req.ClientMsgID, senderName)
	if err != nil {
		log.Printf("[WS] save group message error: %v", err)
		h.sendToUser(cc.userID, map[string]interface{}{
			"type": "message_ack",
			"data": map[string]interface{}{"clientMsgId": req.ClientMsgID, "status": 3, "error": err.Error()},
		})
		return
	}

	// ACK back to sender
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

	if isDup {
		return
	}

	// Get group member count for display
	var memberCnt int64
	database.DB.Model(&model.GroupMember{}).Where("group_id = ?", req.GroupID).Count(&memberCnt)
	groupDisplayName := g.Name

	// Push to all group members concurrently (fan-out)
	var members []model.GroupMember
	database.DB.Where("group_id = ?", req.GroupID).Find(&members)

	pushPayload := map[string]interface{}{
		"type": "new_group_message",
		"data": map[string]interface{}{
			"serverMsgID":    msg.ServerMsgID,
			"clientMsgID":    msg.ClientMsgID,
			"conversationID": msg.ConversationID,
			"groupId":        req.GroupID,
			"groupName":      groupDisplayName,
			"memberCount":    memberCnt,
			"sendID":         msg.SendID,
			"senderName":     msg.SenderName,
			"contentType":    msg.ContentType,
			"content":        msg.Content,
			"sendTime":       msg.SendTime,
			"seq":            msg.Seq,
			"isGroup":        true,
		},
	}

	for _, m := range members {
		if m.UserID == cc.userID {
			continue // skip sender
		}
		memberID := m.UserID
		go h.sendToUser(memberID, pushPayload)
	}
	log.Printf("[WS] group message fanout: groupId=%s seq=%d to %d members", req.GroupID, msg.Seq, len(members))
}

// handleVisibility processes visibility change from H5 client (page hidden/visible).
func (h *ChatHub) handleVisibility(cc *ChatConn, data json.RawMessage) {
	var req struct {
		Visible bool `json:"visible"`
	}
	if err := json.Unmarshal(data, &req); err != nil {
		return
	}

	if req.Visible {
		if cc.visibility == "visible" {
			return
		}
		cc.visibility = "visible"
		h.broadcastClientStatus(cc.userID, "online")
	} else {
		if cc.visibility == "hidden" {
			return
		}
		cc.visibility = "hidden"
		h.broadcastClientStatus(cc.userID, "background")
	}
}

// handleQueryOnline responds with all currently online client users and their status.
func (h *ChatHub) handleQueryOnline(cc *ChatConn) {
	h.mu.RLock()
	var clients []map[string]interface{}
	for _, c := range h.clients {
		if c.role == "client" {
			status := "online"
			if c.visibility == "hidden" {
				status = "background"
			}
			clients = append(clients, map[string]interface{}{
				"userId": c.userID,
				"status": status,
			})
		}
	}
	h.mu.RUnlock()

	h.sendJSON(cc, map[string]interface{}{
		"type": "online_list",
		"data": map[string]interface{}{
			"clients": clients,
		},
	})
}

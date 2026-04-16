package api

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"im-agent-hub/config"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

// ── Audio token ──────────────────────────────────────────────────────────────

type audioTokenPayload struct {
	RoomID string `json:"r"`
	UserID string `json:"u"`
	Exp    int64  `json:"e"`
}

// GenerateAudioToken creates a short-lived HMAC-signed audio room token.
// Both parties in a call receive different tokens for the same roomId.
func GenerateAudioToken(roomID, userID string) string {
	payload, _ := json.Marshal(audioTokenPayload{
		RoomID: roomID,
		UserID: userID,
		Exp:    time.Now().Add(5 * time.Minute).Unix(),
	})
	mac := hmac.New(sha256.New, []byte(config.Cfg.VoiceRelay.Secret))
	mac.Write(payload)
	sig := hex.EncodeToString(mac.Sum(nil))
	return hex.EncodeToString(payload) + "." + sig
}

// GenerateRoomID creates a random 8-byte hex room identifier.
func GenerateRoomID() string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	return "vc_" + hex.EncodeToString(b)
}

// validateAudioToken verifies signature and expiry; returns roomID, userID on success.
func validateAudioToken(raw string) (roomID, userID string, ok bool) {
	dot := strings.LastIndex(raw, ".")
	if dot < 0 {
		return
	}
	payloadHex, sig := raw[:dot], raw[dot+1:]
	payload, err := hex.DecodeString(payloadHex)
	if err != nil {
		return
	}
	mac := hmac.New(sha256.New, []byte(config.Cfg.VoiceRelay.Secret))
	mac.Write(payload)
	expected := hex.EncodeToString(mac.Sum(nil))
	// Constant-time comparison to prevent timing attacks
	if !hmac.Equal([]byte(sig), []byte(expected)) {
		return
	}
	var t audioTokenPayload
	if err := json.Unmarshal(payload, &t); err != nil {
		return
	}
	if time.Now().Unix() > t.Exp {
		return
	}
	return t.RoomID, t.UserID, true
}

// ── Audio relay hub ──────────────────────────────────────────────────────────

// audioWaiter holds the first connection in a room until the second arrives.
type audioWaiter struct {
	conn   *websocket.Conn
	peerCh chan *websocket.Conn // buffered=1; second connection sends itself here
}

var (
	audioRooms   = make(map[string]*audioWaiter)
	audioRoomsMu sync.Mutex
)

// BuildAudioWsUrl constructs the full audio WS URL for a room+token pair.
// If relay_ws_url is configured, use it; otherwise derive from the request Host.
func BuildAudioWsUrl(c *gin.Context, roomID, token string) string {
	base := config.Cfg.VoiceRelay.RelayWsUrl
	if base == "" {
		// Self-relay: use same host as the current request
		scheme := "ws"
		if c.Request.TLS != nil || c.GetHeader("X-Forwarded-Proto") == "https" {
			scheme = "wss"
		}
		base = fmt.Sprintf("%s://%s/api/call/audio", scheme, c.Request.Host)
	}
	return fmt.Sprintf("%s?roomId=%s&token=%s", base, roomID, token)
}

// HandleAudioWS is the WebSocket handler for GET /api/call/audio?roomId=xxx&token=xxx
func HandleAudioWS(c *gin.Context) {
	roomID := c.Query("roomId")
	token := c.Query("token")

	validRoom, _, ok := validateAudioToken(token)
	if !ok || validRoom != roomID {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
		return
	}

	conn, err := wsUpgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Printf("[AudioRelay] upgrade error room=%s: %v", roomID, err)
		return
	}
	conn.SetReadLimit(65536)

	// Join or create room
	audioRoomsMu.Lock()
	waiter, exists := audioRooms[roomID]
	if !exists {
		// First connection: create waiter and store it
		w := &audioWaiter{conn: conn, peerCh: make(chan *websocket.Conn, 1)}
		audioRooms[roomID] = w
		audioRoomsMu.Unlock()

		log.Printf("[AudioRelay] room %s: first connection, waiting for peer", roomID)

		// Block until peer arrives or timeout
		select {
		case peer := <-w.peerCh:
			log.Printf("[AudioRelay] room %s: peer arrived, starting relay", roomID)
			relayAudio(conn, peer)
		case <-time.After(30 * time.Second):
			// No peer within 30s - clean up and close
			audioRoomsMu.Lock()
			if audioRooms[roomID] == w {
				delete(audioRooms, roomID)
			}
			audioRoomsMu.Unlock()
			log.Printf("[AudioRelay] room %s: timeout waiting for peer", roomID)
			conn.Close()
		}
	} else {
		// Second connection: notify first goroutine and relay symmetrically
		peer := waiter.conn
		delete(audioRooms, roomID) // remove from waiter map; room is now active
		audioRoomsMu.Unlock()

		log.Printf("[AudioRelay] room %s: second connection, pairing", roomID)
		waiter.peerCh <- conn // unblock first goroutine
		relayAudio(conn, peer)
	}
}

// buildAudioWsUrlFromConfig returns the configured relay WS base URL
// (e.g. "wss://jp.example.com/api/call/audio").
// Returns empty string when relay_ws_url is not set; clients will use their own server.
func buildAudioWsUrlFromConfig() string {
	return config.Cfg.VoiceRelay.RelayWsUrl
}

// relayAudio reads binary frames from src and writes them to dst.
// Closes dst when src disconnects so the peer's relay goroutine also exits.
func relayAudio(src, dst *websocket.Conn) {
	defer src.Close()
	defer dst.Close()
	for {
		msgType, data, err := src.ReadMessage()
		if err != nil {
			return
		}
		if err := dst.WriteMessage(msgType, data); err != nil {
			return
		}
	}
}

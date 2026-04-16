package api

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"net/http"
	"time"

	"im-agent-hub/config"
	"im-agent-hub/pkg"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

// livekitClaims is the LiveKit access token JWT payload.
type livekitClaims struct {
	Video livekitVideo `json:"video"`
	jwt.RegisteredClaims
}

type livekitVideo struct {
	Room         string `json:"room"`
	RoomJoin     bool   `json:"roomJoin"`
	CanPublish   bool   `json:"canPublish"`
	CanSubscribe bool   `json:"canSubscribe"`
}

func newUUID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// generateLiveKitToken creates a signed LiveKit access token.
func generateLiveKitToken(identity, roomName string) (string, error) {
	cfg := config.Cfg.LiveKit
	now := time.Now()
	claims := livekitClaims{
		Video: livekitVideo{
			Room:         roomName,
			RoomJoin:     true,
			CanPublish:   true,
			CanSubscribe: true,
		},
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    cfg.APIKey,
			Subject:   identity,
			ID:        newUUID(),
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(2 * time.Hour)),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(cfg.APISecret))
}

// LiveKitTokenRequest is the request body for token generation.
type LiveKitTokenRequest struct {
	RoomName string `json:"roomName"` // empty = generate new room
	PeerID   string `json:"peerId"`   // the other participant's ID (for room naming)
}

// LiveKitTokenResponse is returned to the caller.
type LiveKitTokenResponse struct {
	Token    string `json:"token"`
	RoomName string `json:"roomName"`
	WsURL    string `json:"wsUrl"`
}

// ClientLiveKitToken handles POST /api/livekit/token
// Called by H5 user when accepting an incoming call.
func ClientLiveKitToken() gin.HandlerFunc {
	return func(c *gin.Context) {
		userID := c.Query("userId")
		if userID == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "missing userId"})
			return
		}
		var req LiveKitTokenRequest
		_ = c.ShouldBindJSON(&req)
		if req.RoomName == "" {
			// 用户主动发起时自动生成房间名
			req.RoomName = fmt.Sprintf("call_%s_%d", userID, time.Now().UnixMilli())
		}
		token, err := generateLiveKitToken(userID, req.RoomName)
		if err != nil {
			pkg.Fail(c, 500, "token error")
			return
		}
		pkg.Success(c, LiveKitTokenResponse{
			Token:    token,
			RoomName: req.RoomName,
			WsURL:    config.Cfg.LiveKit.WsURL,
		})
	}
}

// ServiceLiveKitToken handles POST /api/service/livekit/token
// Called by PC staff when initiating a call. Creates a new room.
func ServiceLiveKitToken() gin.HandlerFunc {
	return func(c *gin.Context) {
		staffID := c.GetHeader("X-Service-UserID")
		if staffID == "" {
			pkg.Fail(c, 400, "missing staffId")
			return
		}
		var req LiveKitTokenRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			pkg.Fail(c, 400, "invalid request")
			return
		}
		// 如果请求中已有 roomName（接受用户发起的通话），直接使用；否则生成新的
		roomName := req.RoomName
		if roomName == "" {
			roomName = fmt.Sprintf("call_%s_%s_%d", staffID, req.PeerID, time.Now().UnixMilli())
		}
		token, err := generateLiveKitToken(staffID, roomName)
		if err != nil {
			pkg.Fail(c, 500, "token error")
			return
		}
		pkg.Success(c, LiveKitTokenResponse{
			Token:    token,
			RoomName: roomName,
			WsURL:    config.Cfg.LiveKit.WsURL,
		})
	}
}

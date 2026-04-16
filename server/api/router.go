package api

import (
	"net/http"
	"path/filepath"

	"im-agent-hub/service"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
)

// SetupRouter builds and returns the configured Gin engine.
func SetupRouter(
	userSvc *service.UserService,
	msgSvc *service.MessageService,
) *gin.Engine {
	r := gin.Default()

	// Allow all origins during development.
	r.Use(cors.New(cors.Config{
		AllowAllOrigins:  true,
		AllowMethods:     []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Authorization", "X-Service-UserID"},
		ExposeHeaders:    []string{"Content-Length"},
		AllowCredentials: false,
	}))

	// Prevent Edge / IE from caching API responses (fixes "login then back to login" issue).
	r.Use(func(c *gin.Context) {
		if len(c.Request.URL.Path) >= 4 && c.Request.URL.Path[:4] == "/api" {
			c.Header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
			c.Header("Pragma", "no-cache")
			c.Header("Expires", "0")
		}
		c.Next()
	})

	chatHub := NewChatHub(msgSvc)

	// Client auth
	r.POST("/api/client/auth/login", ClientLogin(userSvc))

	// Client WebSocket
	r.GET("/api/ws", chatHub.HandleClientWS)

	// Client LiveKit token (called when accepting an incoming call)
	r.POST("/api/livekit/token", ClientLiveKitToken())

	// Service staff auth
	r.POST("/api/service/auth/login", ServiceLogin())

	// Admin auth (no JWT required)
	r.POST("/api/admin/auth/login", AdminLogin())

	// Serve livekit-client ESM bundle (built by H5 Vite, served locally to avoid CDN blocks)
	r.GET("/lk.js", func(c *gin.Context) {
		matches, err := filepath.Glob("./static/h5/assets/livekit-client*.js")
		if err != nil || len(matches) == 0 {
			c.JSON(http.StatusNotFound, gin.H{"error": "livekit-client bundle not found"})
			return
		}
		c.Header("Content-Type", "application/javascript; charset=utf-8")
		c.Header("Cache-Control", "max-age=3600")
		c.Header("Access-Control-Allow-Origin", "*")
		c.File(matches[0])
	})

	// File upload/download (local storage, bypasses unresolvable MinIO hostname)
	r.POST("/api/upload", UploadFile())
	r.GET("/api/files/*path", ServeUploadedFiles())

	// Lottery data proxy (avoid CORS)
	r.GET("/api/lottery/latest", LotteryLatest())

	// WebSocket for service staff messaging
	r.GET("/api/service/ws", chatHub.HandleStaffWS)

	// Service staff API (token + staff ID required)
	svc := r.Group("/api/service", ServiceTokenAuth())
	{
		svc.GET("/profile", ServiceGetProfile())
		svc.PUT("/profile", ServiceUpdateProfile())
		svc.GET("/contacts", ServiceGetContacts())
		svc.POST("/contacts", ServiceAddUser(userSvc, chatHub))
		svc.PUT("/contacts/:userId", ServiceUpdateContact())

		svc.GET("/groups", ServiceListGroups())
		svc.POST("/groups", ServiceCreateGroup())
		svc.PUT("/groups/:id", ServiceUpdateGroup(chatHub))
		svc.GET("/groups/:id/members", ServiceGetGroupMembers())
		svc.DELETE("/groups/:id", ServiceDissolveGroup(chatHub))
		svc.POST("/groups/:id/members", ServiceInviteToGroup(chatHub))
		svc.DELETE("/groups/:id/members/:userId", ServiceKickFromGroup(chatHub))

		// Staff LiveKit token (called when initiating a call)
		svc.POST("/livekit/token", ServiceLiveKitToken())
	}

	// Admin routes (JWT + admin role required)
	admin := r.Group("/api/admin", JWTAuth(), AdminRequired())
	{
		admin.GET("/stats", GetStats(userSvc, chatHub))

		admin.GET("/users", ListUsers(userSvc))
		admin.POST("/users", CreateUser(userSvc, chatHub))
		admin.POST("/users/batch", BatchCreateUsers(userSvc, chatHub))
		admin.PUT("/users/:id", UpdateUser(userSvc, chatHub))
		admin.DELETE("/users/:id", DeleteUser(userSvc, chatHub))

		admin.GET("/services", ListServiceStaff())
		admin.POST("/services", CreateServiceStaff())
		admin.PUT("/services/:id", UpdateServiceStaff())
		admin.DELETE("/services/:id", DeleteServiceStaff())

		admin.GET("/settings", GetSettings())
		admin.PUT("/settings", UpdateSettings())

		admin.GET("/groups", AdminListGroups())
		admin.POST("/groups", AdminCreateGroup())
		admin.PUT("/groups/:id", AdminUpdateGroup())
		admin.DELETE("/groups/:id", AdminDeleteGroup(chatHub))
	}

	// SPA static files
	setupStaticFiles(r)

	return r
}

// setupStaticFiles registers handlers to serve the two frontend SPAs.
func setupStaticFiles(r *gin.Engine) {
	// H5 SPA assets
	r.Static("/assets", "./static/h5/assets")
	// Admin SPA assets
	r.Static("/admin/assets", "./static/admin/assets")

	r.NoRoute(func(c *gin.Context) {
		path := c.Request.URL.Path
		if len(path) >= 6 && path[:6] == "/admin" {
			c.File("./static/admin/index.html")
			return
		}
		c.File("./static/h5/index.html")
	})
}

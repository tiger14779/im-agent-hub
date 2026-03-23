package api

import (
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

	chatHub := NewChatHub(msgSvc)

	// Client auth
	r.POST("/api/client/auth/login", ClientLogin(userSvc))

	// Client WebSocket
	r.GET("/api/ws", chatHub.HandleClientWS)

	// Service staff auth
	r.POST("/api/service/auth/login", ServiceLogin())

	// Admin auth (no JWT required)
	r.POST("/api/admin/auth/login", AdminLogin())

	// File upload/download (local storage, bypasses unresolvable MinIO hostname)
	r.POST("/api/upload", UploadFile())
	r.GET("/api/files/*path", ServeUploadedFiles())

	// WebSocket for service staff messaging
	r.GET("/api/service/ws", chatHub.HandleStaffWS)

	// Service staff API (token + staff ID required)
	svc := r.Group("/api/service", ServiceTokenAuth())
	{
		svc.GET("/profile", ServiceGetProfile())
		svc.GET("/contacts", ServiceGetContacts())
		svc.POST("/contacts", ServiceAddUser(userSvc))
		svc.PUT("/contacts/:userId", ServiceUpdateContact())
	}

	// Admin routes (JWT + admin role required)
	admin := r.Group("/api/admin", JWTAuth(), AdminRequired())
	{
		admin.GET("/stats", GetStats(userSvc, chatHub))

		admin.GET("/users", ListUsers(userSvc))
		admin.POST("/users", CreateUser(userSvc))
		admin.POST("/users/batch", BatchCreateUsers(userSvc))
		admin.PUT("/users/:id", UpdateUser(userSvc))
		admin.DELETE("/users/:id", DeleteUser(userSvc))

		admin.GET("/services", ListServiceStaff())
		admin.POST("/services", CreateServiceStaff())
		admin.PUT("/services/:id", UpdateServiceStaff())
		admin.DELETE("/services/:id", DeleteServiceStaff())

		admin.GET("/settings", GetSettings())
		admin.PUT("/settings", UpdateSettings())
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

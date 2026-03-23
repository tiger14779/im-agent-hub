package api

import (
	"im-agent-hub/service"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
)

// SetupRouter builds and returns the configured Gin engine.
func SetupRouter(
	userSvc *service.UserService,
	openIMSvc *service.OpenIMService,
) *gin.Engine {
	r := gin.Default()

	// Allow all origins during development.
	r.Use(cors.New(cors.Config{
		AllowAllOrigins:  true,
		AllowMethods:     []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Authorization"},
		ExposeHeaders:    []string{"Content-Length"},
		AllowCredentials: false,
	}))

	// Client auth
	r.POST("/api/client/auth/login", ClientLogin(userSvc, openIMSvc))

	// Service staff auth
	r.POST("/api/service/auth/login", ServiceLogin(openIMSvc))

	// Admin auth (no JWT required)
	r.POST("/api/admin/auth/login", AdminLogin())

	// File upload/download (local storage, bypasses unresolvable MinIO hostname)
	r.POST("/api/upload", UploadFile())
	r.GET("/api/files/*path", ServeUploadedFiles())

	// Admin routes (JWT + admin role required)
	admin := r.Group("/api/admin", JWTAuth(), AdminRequired())
	{
		admin.GET("/stats", GetStats(userSvc, openIMSvc))

		admin.GET("/users", ListUsers(userSvc))
		admin.POST("/users", CreateUser(userSvc))
		admin.POST("/users/batch", BatchCreateUsers(userSvc))
		admin.PUT("/users/:id", UpdateUser(userSvc))
		admin.DELETE("/users/:id", DeleteUser(userSvc))

		admin.GET("/services", ListServiceStaff())
		admin.POST("/services", CreateServiceStaff(openIMSvc))
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
	// Admin SPA — must be registered before the wildcard catch-all.
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

package api

import (
	"im-agent-hub/config"
	"im-agent-hub/database"
	"im-agent-hub/model"
	"im-agent-hub/pkg"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

type adminLoginReq struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

// AdminLogin handles POST /api/admin/auth/login.
func AdminLogin() gin.HandlerFunc {
	return func(c *gin.Context) {
		var req adminLoginReq
		if err := c.ShouldBindJSON(&req); err != nil {
			pkg.Fail(c, 400, "username and password are required")
			return
		}

		var admin model.Admin
		if err := database.DB.Where("username = ?", req.Username).First(&admin).Error; err != nil {
			pkg.Fail(c, 401, "invalid credentials")
			return
		}

		if err := bcrypt.CompareHashAndPassword([]byte(admin.Password), []byte(req.Password)); err != nil {
			pkg.Fail(c, 401, "invalid credentials")
			return
		}

		token, err := pkg.GenerateToken(admin.Username, true, config.Cfg.Server.JWTSecret)
		if err != nil {
			pkg.Fail(c, 500, "failed to generate token")
			return
		}

		pkg.Success(c, gin.H{"token": token})
	}
}

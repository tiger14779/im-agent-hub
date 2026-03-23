package api

import (
	"im-agent-hub/config"
	"im-agent-hub/pkg"
	"im-agent-hub/service"

	"github.com/gin-gonic/gin"
)

type clientLoginReq struct {
	UserID string `json:"userId" binding:"required"`
}

// ClientLogin handles POST /api/client/auth/login.
// It looks up the user and returns a JWT token + serviceUserId.
func ClientLogin(userSvc *service.UserService) gin.HandlerFunc {
	return func(c *gin.Context) {
		var req clientLoginReq
		if err := c.ShouldBindJSON(&req); err != nil {
			pkg.Fail(c, 400, "userId is required")
			return
		}

		user, err := userSvc.GetUserByID(req.UserID)
		if err != nil {
			pkg.Fail(c, 404, "user not found")
			return
		}

		if user.Status != 1 {
			pkg.Fail(c, 403, "account is disabled")
			return
		}

		token, err := pkg.GenerateToken(user.ID, false, config.Cfg.Server.JWTSecret)
		if err != nil {
			pkg.Fail(c, 500, "failed to generate token")
			return
		}

		pkg.Success(c, gin.H{
			"token":         token,
			"userId":        user.ID,
			"nickname":      user.Nickname,
			"serviceUserId": user.ServiceUserID,
		})
	}
}

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
// It looks up the user, fetches an OpenIM token, and returns connection info.
func ClientLogin(userSvc *service.UserService, openIMSvc *service.OpenIMService) gin.HandlerFunc {
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

		token, err := openIMSvc.GetUserToken(user.ID)
		if err != nil {
			pkg.Fail(c, 500, "failed to obtain im token: "+err.Error())
			return
		}

		pkg.Success(c, gin.H{
			"token":         token,
			"serviceUserId": user.ServiceUserID,
			"wsUrl":         config.Cfg.OpenIM.WSURL,
			"apiUrl":        config.Cfg.OpenIM.APIURL,
		})
	}
}

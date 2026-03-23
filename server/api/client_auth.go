package api

import (
	"log"

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

		// Ensure the client user itself is registered in OpenIM
		if err := openIMSvc.EnsureUserRegistered(user.ID, user.Nickname); err != nil {
			log.Printf("[ClientLogin] EnsureUserRegistered(%s) failed: %v", user.ID, err)
			pkg.Fail(c, 500, "OpenIM用户注册失败: "+err.Error())
			return
		}

		if user.ServiceUserID != "" {
			if err := openIMSvc.EnsureUserRegistered(user.ServiceUserID, "客服"); err != nil {
				log.Printf("[ClientLogin] EnsureUserRegistered(service=%s) failed: %v", user.ServiceUserID, err)
				pkg.Fail(c, 500, "客服用户注册失败: "+err.Error())
				return
			}
		}

		token, err := openIMSvc.GetUserToken(user.ID)
		if err != nil {
			log.Printf("[ClientLogin] GetUserToken(%s) failed: %v", user.ID, err)
			pkg.Fail(c, 500, "获取IM令牌失败: "+err.Error())
			return
		}

		log.Printf("[ClientLogin] user=%s serviceUser=%s token_len=%d", user.ID, user.ServiceUserID, len(token))

		pkg.Success(c, gin.H{
			"token":         token,
			"serviceUserId": user.ServiceUserID,
			"wsUrl":         config.Cfg.OpenIM.WSURL,
			"apiUrl":        config.Cfg.OpenIM.APIURL,
		})
	}
}

package api

import (
	"im-agent-hub/config"
	"im-agent-hub/database"
	"im-agent-hub/model"
	"im-agent-hub/pkg"
	"im-agent-hub/service"

	"github.com/gin-gonic/gin"
)

type serviceLoginReq struct {
	UserID string `json:"userId" binding:"required"`
}

// ServiceLogin handles POST /api/service/auth/login.
// It looks up the service staff, fetches an OpenIM token, and returns connection info
// along with the list of users assigned to this service staff.
func ServiceLogin(openIMSvc *service.OpenIMService) gin.HandlerFunc {
	return func(c *gin.Context) {
		var req serviceLoginReq
		if err := c.ShouldBindJSON(&req); err != nil {
			pkg.Fail(c, 400, "userId is required")
			return
		}

		// Look up service staff
		var staff model.ServiceStaff
		if err := database.DB.First(&staff, "user_id = ?", req.UserID).Error; err != nil {
			pkg.Fail(c, 404, "service staff not found")
			return
		}

		if staff.Status != 1 {
			pkg.Fail(c, 403, "account is disabled")
			return
		}

		// Ensure registered in OpenIM
		if err := openIMSvc.EnsureUserRegistered(staff.UserID, staff.Nickname); err != nil {
			pkg.Fail(c, 500, "failed to ensure service user in openim: "+err.Error())
			return
		}

		token, err := openIMSvc.GetUserToken(staff.UserID)
		if err != nil {
			pkg.Fail(c, 500, "failed to obtain im token: "+err.Error())
			return
		}

		// Find all users assigned to this service staff
		var users []model.User
		database.DB.Where("service_user_id = ? AND status = 1", staff.UserID).
			Order("created_at desc").Find(&users)

		type userItem struct {
			UserID   string `json:"userId"`
			Nickname string `json:"nickname"`
		}
		userList := make([]userItem, 0, len(users))
		for _, u := range users {
			userList = append(userList, userItem{UserID: u.ID, Nickname: u.Nickname})
		}

		pkg.Success(c, gin.H{
			"token":    token,
			"userId":   staff.UserID,
			"nickname": staff.Nickname,
			"wsUrl":    config.Cfg.OpenIM.WSURL,
			"apiUrl":   config.Cfg.OpenIM.APIURL,
			"users":    userList,
		})
	}
}

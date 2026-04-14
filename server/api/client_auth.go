package api

import (
	"im-agent-hub/config"
	"im-agent-hub/database"
	"im-agent-hub/model"
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

		// Look up service staff info for the client to display
		serviceNickname := "客服"
		serviceAvatar := ""
		var staff model.ServiceStaff
		if err := database.DB.First(&staff, "user_id = ?", user.ServiceUserID).Error; err == nil {
			if staff.Nickname != "" {
				serviceNickname = staff.Nickname
			}
			serviceAvatar = staff.Avatar
		}

		// Get groups this user is a member of
		var groupMembers []model.GroupMember
		database.DB.Where("user_id = ?", user.ID).Find(&groupMembers)
		type groupInfo struct {
			GroupID string `json:"groupId"`
			Name    string `json:"name"`
			Avatar  string `json:"avatar"`
		}
		groupInfoList := make([]groupInfo, 0)
		if len(groupMembers) > 0 {
			groupIDs := make([]string, 0, len(groupMembers))
			for _, gm := range groupMembers {
				groupIDs = append(groupIDs, gm.GroupID)
			}
			var userGroups []model.Group
			database.DB.Where("id IN ? AND dissolved = ?", groupIDs, false).Find(&userGroups)
			for _, g := range userGroups {
				groupInfoList = append(groupInfoList, groupInfo{GroupID: g.ID, Name: g.Name, Avatar: g.Avatar})
			}
		}

		pkg.Success(c, gin.H{
			"token":           token,
			"userId":          user.ID,
			"nickname":        user.Nickname,
			"avatar":          user.Avatar,
			"serviceUserId":   user.ServiceUserID,
			"serviceNickname": serviceNickname,
			"serviceAvatar":   serviceAvatar,
			"groups":          groupInfoList,
		})
	}
}

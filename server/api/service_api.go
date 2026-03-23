package api

import (
	"im-agent-hub/database"
	"im-agent-hub/model"
	"im-agent-hub/pkg"
	"im-agent-hub/service"

	"github.com/gin-gonic/gin"
)

// ServiceGetContacts returns the list of users assigned to the logged-in service staff.
// GET /api/service/contacts
func ServiceGetContacts() gin.HandlerFunc {
	return func(c *gin.Context) {
		staffID := c.GetString("serviceUserId")
		if staffID == "" {
			pkg.Fail(c, 401, "未登录")
			return
		}

		var users []model.User
		database.DB.Where("service_user_id = ? AND status = 1", staffID).
			Order("updated_at desc").Find(&users)

		type contactItem struct {
			UserID   string `json:"userId"`
			Nickname string `json:"nickname"`
			Remark   string `json:"remark"`
			Avatar   string `json:"avatar"`
		}
		list := make([]contactItem, 0, len(users))
		for _, u := range users {
			list = append(list, contactItem{
				UserID:   u.ID,
				Nickname: u.Nickname,
				Remark:   u.Remark,
				Avatar:   u.Avatar,
			})
		}

		pkg.Success(c, list)
	}
}

// ServiceAddUser creates a new user directly under the current service staff.
// POST /api/service/contacts
func ServiceAddUser(userSvc *service.UserService) gin.HandlerFunc {
	return func(c *gin.Context) {
		staffID := c.GetString("serviceUserId")
		if staffID == "" {
			pkg.Fail(c, 401, "未登录")
			return
		}

		var req struct {
			Nickname string `json:"nickname" binding:"required"`
			Remark   string `json:"remark"`
			Avatar   string `json:"avatar"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			pkg.Fail(c, 400, "nickname is required")
			return
		}

		user, err := userSvc.CreateUser(req.Nickname, staffID)
		if err != nil {
			pkg.Fail(c, 500, "创建用户失败: "+err.Error())
			return
		}

		// Update remark and avatar if provided
		updates := map[string]interface{}{}
		if req.Remark != "" {
			updates["remark"] = req.Remark
		}
		if req.Avatar != "" {
			updates["avatar"] = req.Avatar
		}
		if len(updates) > 0 {
			database.DB.Model(&model.User{}).Where("id = ?", user.ID).Updates(updates)
		}

		pkg.Success(c, gin.H{
			"userId":   user.ID,
			"nickname": user.Nickname,
			"remark":   req.Remark,
			"avatar":   req.Avatar,
		})
	}
}

// ServiceUpdateContact updates the remark and/or avatar for a user.
// PUT /api/service/contacts/:userId
func ServiceUpdateContact() gin.HandlerFunc {
	return func(c *gin.Context) {
		staffID := c.GetString("serviceUserId")
		userID := c.Param("userId")

		// Verify ownership
		var user model.User
		if err := database.DB.First(&user, "id = ? AND service_user_id = ?", userID, staffID).Error; err != nil {
			pkg.Fail(c, 404, "用户不存在或不属于当前客服")
			return
		}

		var req struct {
			Remark *string `json:"remark"`
			Avatar *string `json:"avatar"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			pkg.Fail(c, 400, "invalid request")
			return
		}

		updates := map[string]interface{}{}
		if req.Remark != nil {
			updates["remark"] = *req.Remark
		}
		if req.Avatar != nil {
			updates["avatar"] = *req.Avatar
		}
		if len(updates) == 0 {
			pkg.Fail(c, 400, "nothing to update")
			return
		}

		database.DB.Model(&model.User{}).Where("id = ?", userID).Updates(updates)

		// Re-read
		database.DB.First(&user, "id = ?", userID)
		pkg.Success(c, gin.H{
			"userId":   user.ID,
			"nickname": user.Nickname,
			"remark":   user.Remark,
			"avatar":   user.Avatar,
		})
	}
}

// ServiceTokenAuth middleware verifies the OpenIM token from the service staff login.
// It stores the serviceUserId in the context for downstream handlers.
func ServiceTokenAuth() gin.HandlerFunc {
	return func(c *gin.Context) {
		token := c.GetHeader("Authorization")
		staffID := c.GetHeader("X-Service-UserID")
		if token == "" || staffID == "" {
			pkg.Fail(c, 401, "missing auth headers")
			c.Abort()
			return
		}
		// Verify staff exists
		var staff model.ServiceStaff
		if err := database.DB.First(&staff, "user_id = ?", staffID).Error; err != nil {
			pkg.Fail(c, 401, "service staff not found")
			c.Abort()
			return
		}
		c.Set("serviceUserId", staffID)
		c.Set("serviceToken", token)
		c.Next()
	}
}

// ServiceGetProfile returns the service staff's own profile info.
// GET /api/service/profile
func ServiceGetProfile() gin.HandlerFunc {
	return func(c *gin.Context) {
		staffID := c.GetString("serviceUserId")
		var staff model.ServiceStaff
		if err := database.DB.First(&staff, "user_id = ?", staffID).Error; err != nil {
			pkg.Fail(c, 404, "not found")
			return
		}
		pkg.Success(c, gin.H{
			"userId":   staff.UserID,
			"nickname": staff.Nickname,
			"avatar":   staff.Avatar,
		})
	}
}

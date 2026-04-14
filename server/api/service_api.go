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

		// Build a map of conversations for this staff member
		var convs []model.Conversation
		database.DB.Where("user_a = ? OR user_b = ?", staffID, staffID).Find(&convs)
		convMap := make(map[string]*model.Conversation, len(convs))
		for i := range convs {
			// Key by the peer user ID
			peer := convs[i].UserA
			if peer == staffID {
				peer = convs[i].UserB
			}
			convMap[peer] = &convs[i]
		}

		type contactItem struct {
			UserID      string `json:"userId"`
			Nickname    string `json:"nickname"`
			Avatar      string `json:"avatar"`
			UnreadCount int    `json:"unreadCount"`
			LastMessage string `json:"lastMessage"`
			LastTime    int64  `json:"lastTime"`
		}
		list := make([]contactItem, 0, len(users))
		for _, u := range users {
			item := contactItem{
				UserID:   u.ID,
				Nickname: u.Nickname,
				Avatar:   u.Avatar,
			}
			if conv, ok := convMap[u.ID]; ok {
				if staffID == conv.UserA {
					item.UnreadCount = conv.UnreadA
				} else {
					item.UnreadCount = conv.UnreadB
				}
				item.LastMessage = conv.LastMsgContent
				item.LastTime = conv.LastMsgTime
			}
			list = append(list, item)
		}

		pkg.Success(c, list)
	}
}

// ServiceAddUser creates a new user directly under the current service staff.
// POST /api/service/contacts
func ServiceAddUser(userSvc *service.UserService, chatHub *ChatHub) gin.HandlerFunc {
	return func(c *gin.Context) {
		staffID := c.GetString("serviceUserId")
		if staffID == "" {
			pkg.Fail(c, 401, "未登录")
			return
		}

		var req struct {
			Nickname      string `json:"nickname" binding:"required"`
			GroupNickname string `json:"groupNickname" binding:"required"`
			Avatar        string `json:"avatar"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			pkg.Fail(c, 400, "nickname and groupNickname are required")
			return
		}

		user, err := userSvc.CreateUser(req.Nickname, req.GroupNickname, staffID)
		if err != nil {
			pkg.Fail(c, 500, "创建用户失败: "+err.Error())
			return
		}

		// Update avatar if provided
		if req.Avatar != "" {
			database.DB.Model(&model.User{}).Where("id = ?", user.ID).Updates(map[string]interface{}{"avatar": req.Avatar})
		}

		chatHub.NotifyContactsUpdated(staffID)

		pkg.Success(c, gin.H{
			"userId":        user.ID,
			"nickname":      user.Nickname,
			"groupNickname": user.GroupNickname,
			"avatar":        req.Avatar,
		})
	}
}

// ServiceUpdateContact updates the nickname and/or avatar for a user.
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
			Nickname      *string `json:"nickname"`
			GroupNickname *string `json:"groupNickname"`
			Avatar        *string `json:"avatar"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			pkg.Fail(c, 400, "invalid request")
			return
		}

		updates := map[string]interface{}{}
		if req.Nickname != nil {
			updates["nickname"] = *req.Nickname
		}
		if req.GroupNickname != nil {
			updates["group_nickname"] = *req.GroupNickname
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
			"userId":        user.ID,
			"nickname":      user.Nickname,
			"groupNickname": user.GroupNickname,
			"avatar":        user.Avatar,
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

// ServiceUpdateProfile updates the service staff's own nickname and avatar.
// PUT /api/service/profile
func ServiceUpdateProfile() gin.HandlerFunc {
	return func(c *gin.Context) {
		staffID := c.GetString("serviceUserId")
		var req struct {
			Nickname *string `json:"nickname"`
			Avatar   *string `json:"avatar"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			pkg.Fail(c, 400, "invalid request")
			return
		}
		updates := map[string]interface{}{}
		if req.Nickname != nil {
			updates["nickname"] = *req.Nickname
		}
		if req.Avatar != nil {
			updates["avatar"] = *req.Avatar
		}
		if len(updates) == 0 {
			pkg.Fail(c, 400, "nothing to update")
			return
		}
		database.DB.Model(&model.ServiceStaff{}).Where("user_id = ?", staffID).Updates(updates)
		var staff model.ServiceStaff
		database.DB.First(&staff, "user_id = ?", staffID)
		pkg.Success(c, gin.H{
			"userId":   staff.UserID,
			"nickname": staff.Nickname,
			"avatar":   staff.Avatar,
		})
	}
}

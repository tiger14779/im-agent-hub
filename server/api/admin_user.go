package api

import (
	"strconv"

	"im-agent-hub/pkg"
	"im-agent-hub/service"

	"github.com/gin-gonic/gin"
)

// ListUsers handles GET /api/admin/users
func ListUsers(svc *service.UserService) gin.HandlerFunc {
	return func(c *gin.Context) {
		page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
		pageSize, _ := strconv.Atoi(c.DefaultQuery("pageSize", "20"))
		if page < 1 {
			page = 1
		}
		if pageSize < 1 || pageSize > 100 {
			pageSize = 20
		}

		users, total, err := svc.GetUsers(page, pageSize)
		if err != nil {
			pkg.Fail(c, 500, err.Error())
			return
		}
		pkg.Success(c, gin.H{"list": users, "total": total, "page": page, "pageSize": pageSize})
	}
}

type createUserReq struct {
	Nickname      string `json:"nickname" binding:"required"`
	ServiceUserID string `json:"serviceUserId" binding:"required"`
	Avatar        string `json:"avatar"`
}

// CreateUser handles POST /api/admin/users
func CreateUser(svc *service.UserService, chatHub *ChatHub) gin.HandlerFunc {
	return func(c *gin.Context) {
		var req createUserReq
		if err := c.ShouldBindJSON(&req); err != nil {
			pkg.Fail(c, 400, "nickname and serviceUserId are required")
			return
		}

		user, err := svc.CreateUser(req.Nickname, req.ServiceUserID)
		if err != nil {
			pkg.Fail(c, 500, err.Error())
			return
		}
		if req.Avatar != "" {
			svc.UpdateAvatar(user.ID, req.Avatar)
			user.Avatar = req.Avatar
		}
		chatHub.NotifyContactsUpdated(req.ServiceUserID)
		pkg.Success(c, user)
	}
}

type updateUserReq struct {
	Nickname      string `json:"nickname" binding:"required"`
	ServiceUserID string `json:"serviceUserId" binding:"required"`
	Avatar        string `json:"avatar"`
}

// UpdateUser handles PUT /api/admin/users/:id
func UpdateUser(svc *service.UserService, chatHub *ChatHub) gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.Param("id")
		var req updateUserReq
		if err := c.ShouldBindJSON(&req); err != nil {
			pkg.Fail(c, 400, "nickname and serviceUserId are required")
			return
		}

		user, err := svc.UpdateUser(id, req.Nickname, req.ServiceUserID)
		if err != nil {
			pkg.Fail(c, 404, err.Error())
			return
		}
		if req.Avatar != "" {
			svc.UpdateAvatar(user.ID, req.Avatar)
			user.Avatar = req.Avatar
		}
		chatHub.NotifyContactsUpdated(req.ServiceUserID)
		pkg.Success(c, user)
	}
}

// DeleteUser handles DELETE /api/admin/users/:id
func DeleteUser(svc *service.UserService, chatHub *ChatHub) gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.Param("id")
		// Look up the user's serviceUserId before deleting
		user, _ := svc.GetUserByID(id)
		if err := svc.DeleteUser(id); err != nil {
			pkg.Fail(c, 404, err.Error())
			return
		}
		if user != nil && user.ServiceUserID != "" {
			chatHub.NotifyContactsUpdated(user.ServiceUserID)
		}
		pkg.Success(c, nil)
	}
}

type batchCreateReq struct {
	Count         int    `json:"count" binding:"required,min=1,max=100"`
	ServiceUserID string `json:"serviceUserId" binding:"required"`
}

// BatchCreateUsers handles POST /api/admin/users/batch
func BatchCreateUsers(svc *service.UserService, chatHub *ChatHub) gin.HandlerFunc {
	return func(c *gin.Context) {
		var req batchCreateReq
		if err := c.ShouldBindJSON(&req); err != nil {
			pkg.Fail(c, 400, "count (1-100) and serviceUserId are required")
			return
		}

		users, err := svc.BatchCreateUsers(req.Count, req.ServiceUserID)
		if err != nil {
			pkg.Fail(c, 500, err.Error())
			return
		}
		chatHub.NotifyContactsUpdated(req.ServiceUserID)
		pkg.Success(c, gin.H{"list": users, "total": len(users)})
	}
}

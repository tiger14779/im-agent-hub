package api

import (
	"im-agent-hub/database"
	"im-agent-hub/model"
	"im-agent-hub/pkg"

	"github.com/gin-gonic/gin"
)

// ListServiceStaff handles GET /api/admin/services
func ListServiceStaff() gin.HandlerFunc {
	return func(c *gin.Context) {
		var staff []model.ServiceStaff
		if err := database.DB.Order("created_at desc").Find(&staff).Error; err != nil {
			pkg.Fail(c, 500, err.Error())
			return
		}
		pkg.Success(c, gin.H{"list": staff, "total": len(staff)})
	}
}

type createStaffReq struct {
	UserID   string `json:"userId" binding:"required"`
	Nickname string `json:"nickname" binding:"required"`
	Avatar   string `json:"avatar"`
}

// CreateServiceStaff handles POST /api/admin/services
func CreateServiceStaff() gin.HandlerFunc {
	return func(c *gin.Context) {
		var req createStaffReq
		if err := c.ShouldBindJSON(&req); err != nil {
			pkg.Fail(c, 400, "userId and nickname are required")
			return
		}

		staff := model.ServiceStaff{
			UserID:   req.UserID,
			Nickname: req.Nickname,
			Avatar:   req.Avatar,
			Status:   1,
		}
		if err := database.DB.Create(&staff).Error; err != nil {
			pkg.Fail(c, 500, err.Error())
			return
		}
		pkg.Success(c, staff)
	}
}

type updateStaffReq struct {
	Nickname string `json:"nickname"`
	Avatar   string `json:"avatar"`
	Status   *int   `json:"status"`
}

// UpdateServiceStaff handles PUT /api/admin/services/:id
func UpdateServiceStaff() gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.Param("id")
		var req updateStaffReq
		if err := c.ShouldBindJSON(&req); err != nil {
			pkg.Fail(c, 400, err.Error())
			return
		}

		var staff model.ServiceStaff
		if err := database.DB.First(&staff, "user_id = ?", id).Error; err != nil {
			pkg.Fail(c, 404, "service staff not found")
			return
		}

		if req.Nickname != "" {
			staff.Nickname = req.Nickname
		}
		if req.Avatar != "" {
			staff.Avatar = req.Avatar
		}
		if req.Status != nil {
			staff.Status = *req.Status
		}

		if err := database.DB.Save(&staff).Error; err != nil {
			pkg.Fail(c, 500, err.Error())
			return
		}
		pkg.Success(c, staff)
	}
}

// DeleteServiceStaff handles DELETE /api/admin/services/:id
func DeleteServiceStaff() gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.Param("id")
		result := database.DB.Delete(&model.ServiceStaff{}, "user_id = ?", id)
		if result.Error != nil {
			pkg.Fail(c, 500, result.Error.Error())
			return
		}
		if result.RowsAffected == 0 {
			pkg.Fail(c, 404, "service staff not found")
			return
		}
		pkg.Success(c, nil)
	}
}

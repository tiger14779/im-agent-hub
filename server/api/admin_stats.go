package api

import (
	"time"

	"im-agent-hub/database"
	"im-agent-hub/model"
	"im-agent-hub/pkg"
	"im-agent-hub/service"

	"github.com/gin-gonic/gin"
)

// GetStats handles GET /api/admin/stats
func GetStats(userSvc *service.UserService, openIMSvc *service.OpenIMService) gin.HandlerFunc {
	return func(c *gin.Context) {
		var totalUsers int64
		database.DB.Model(&model.User{}).Count(&totalUsers)

		var todayUsers int64
		today := time.Now().Truncate(24 * time.Hour)
		database.DB.Model(&model.User{}).Where("created_at >= ?", today).Count(&todayUsers)

		var staffCount int64
		database.DB.Model(&model.ServiceStaff{}).Count(&staffCount)

		// Fetch all user IDs to query online status.
		var users []model.User
		database.DB.Select("id").Find(&users)
		userIDs := make([]string, len(users))
		for i, u := range users {
			userIDs[i] = u.ID
		}

		onlineCount := 0
		if len(userIDs) > 0 {
			if n, err := openIMSvc.GetOnlineUsers(userIDs); err == nil {
				onlineCount = n
			}
		}

		pkg.Success(c, gin.H{
			"totalUsers":   totalUsers,
			"todayNew":     todayUsers,
			"serviceCount": staffCount,
			"onlineUsers":  onlineCount,
		})
	}
}

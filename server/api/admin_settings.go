package api

import (
	"fmt"

	"im-agent-hub/config"
	"im-agent-hub/pkg"

	"github.com/gin-gonic/gin"
	"github.com/robfig/cron/v3"
)

// GetSettings handles GET /api/admin/settings
func GetSettings() gin.HandlerFunc {
	return func(c *gin.Context) {
		cfg := config.Cfg.Cleanup
		pkg.Success(c, gin.H{
			"enabled":       cfg.Enabled,
			"retentionDays": cfg.RetentionDays,
			"cron":          cfg.Cron,
		})
	}
}

type updateSettingsReq struct {
	RetentionDays *int   `json:"retentionDays"`
	Cron          string `json:"cron"`
}

// UpdateSettings handles PUT /api/admin/settings
// Updates the in-memory cleanup configuration (changes persist until restart).
func UpdateSettings() gin.HandlerFunc {
	return func(c *gin.Context) {
		var req updateSettingsReq
		if err := c.ShouldBindJSON(&req); err != nil {
			pkg.Fail(c, 400, err.Error())
			return
		}

		if req.RetentionDays != nil {
			if *req.RetentionDays < 1 {
				pkg.Fail(c, 400, "retentionDays must be at least 1")
				return
			}
			config.Cfg.Cleanup.RetentionDays = *req.RetentionDays
		}
		if req.Cron != "" {
			if err := validateCron(req.Cron); err != nil {
				pkg.Fail(c, 400, fmt.Sprintf("invalid cron expression: %v", err))
				return
			}
			config.Cfg.Cleanup.Cron = req.Cron
		}

		pkg.Success(c, gin.H{
			"enabled":       config.Cfg.Cleanup.Enabled,
			"retentionDays": config.Cfg.Cleanup.RetentionDays,
			"cron":          config.Cfg.Cleanup.Cron,
		})
	}
}

// validateCron checks that expr is a valid 5-field cron expression.
func validateCron(expr string) error {
	_, err := cron.ParseStandard(expr)
	return err
}

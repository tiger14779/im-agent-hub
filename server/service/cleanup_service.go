package service

import (
	"log"
	"time"

	"im-agent-hub/config"
	"im-agent-hub/database"
	"im-agent-hub/model"

	"github.com/robfig/cron/v3"
)

// CleanupService schedules periodic message cleanup via OpenIM.
type CleanupService struct {
	openIM    *OpenIMService
	scheduler *cron.Cron
}

// NewCleanupService creates a CleanupService backed by the given OpenIM service.
func NewCleanupService(openIM *OpenIMService) *CleanupService {
	return &CleanupService{
		openIM:    openIM,
		scheduler: cron.New(),
	}
}

// StartCleanup registers and starts the cleanup cron job when enabled.
func (s *CleanupService) StartCleanup() {
	cfg := config.Cfg.Cleanup
	if !cfg.Enabled {
		log.Println("cleanup: disabled, skipping cron registration")
		return
	}

	_, err := s.scheduler.AddFunc(cfg.Cron, s.runCleanup)
	if err != nil {
		log.Printf("cleanup: failed to register cron job: %v", err)
		return
	}

	s.scheduler.Start()
	log.Printf("cleanup: cron job scheduled with expression %q (retention: %d days)", cfg.Cron, cfg.RetentionDays)
}

// runCleanup iterates over all users and asks OpenIM to clear old messages.
func (s *CleanupService) runCleanup() {
	retentionDays := config.Cfg.Cleanup.RetentionDays
	cutoff := time.Now().AddDate(0, 0, -retentionDays)
	log.Printf("cleanup: starting — removing messages older than %s", cutoff.Format(time.RFC3339))

	var users []model.User
	if err := database.DB.Find(&users).Error; err != nil {
		log.Printf("cleanup: failed to fetch users: %v", err)
		return
	}

	success, failed := 0, 0
	for _, u := range users {
		if err := s.openIM.DeleteMessages(u.ID, cutoff); err != nil {
			log.Printf("cleanup: failed for user %s: %v", u.ID, err)
			failed++
		} else {
			success++
		}
	}

	log.Printf("cleanup: finished — success=%d, failed=%d", success, failed)
}

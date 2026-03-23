package service

import (
	"log"

	"im-agent-hub/config"

	"github.com/robfig/cron/v3"
)

// CleanupService schedules periodic message cleanup.
type CleanupService struct {
	msgSvc    *MessageService
	scheduler *cron.Cron
}

// NewCleanupService creates a CleanupService backed by the given MessageService.
func NewCleanupService(msgSvc *MessageService) *CleanupService {
	return &CleanupService{
		msgSvc:    msgSvc,
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

// runCleanup deletes messages older than the configured retention period.
func (s *CleanupService) runCleanup() {
	retentionDays := config.Cfg.Cleanup.RetentionDays
	deleted, err := s.msgSvc.CleanupOldMessages(retentionDays)
	if err != nil {
		log.Printf("cleanup: error: %v", err)
		return
	}
	log.Printf("cleanup: finished — deleted %d messages", deleted)
}

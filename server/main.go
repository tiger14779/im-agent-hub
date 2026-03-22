package main

import (
	"fmt"
	"log"

	"im-agent-hub/api"
	"im-agent-hub/config"
	"im-agent-hub/database"
	"im-agent-hub/service"
)

func main() {
	config.LoadConfig("./config/config.yaml")

	database.Init()

	openIMSvc := service.NewOpenIMService(
		config.Cfg.OpenIM.APIURL,
		config.Cfg.OpenIM.AdminUserID,
		config.Cfg.OpenIM.Secret,
	)

	userSvc := service.NewUserService(openIMSvc)

	cleanupSvc := service.NewCleanupService(openIMSvc)
	cleanupSvc.StartCleanup()

	router := api.SetupRouter(userSvc, openIMSvc)

	addr := fmt.Sprintf(":%d", config.Cfg.Server.Port)
	log.Printf("server starting on %s", addr)
	if err := router.Run(addr); err != nil {
		log.Fatalf("server error: %v", err)
	}
}

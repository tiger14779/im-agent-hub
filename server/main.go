package main

import (
	"fmt"
	"log"
	"os"

	"im-agent-hub/api"
	"im-agent-hub/config"
	"im-agent-hub/database"
	"im-agent-hub/service"
)

func main() {
	configPath := os.Getenv("IM_AGENT_HUB_CONFIG")
	if configPath == "" {
		if _, err := os.Stat("./config/config.local.yaml"); err == nil {
			configPath = "./config/config.local.yaml"
		} else {
			configPath = "./config/config.yaml"
		}
	}

	config.LoadConfig(configPath)
	log.Printf("config loaded from %s", configPath)

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
